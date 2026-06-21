# Versioned backup of the OpenTofu state mirror (homelab-iac). The mirror dir
# (written by the minio-tfstate-mirror container) is one copy on discovery's
# primary SSD; this snapshots it with restic onto a separate physical disk
# (vault / sdb) for point-in-time history + integrity. Off-host redundancy is
# handled separately by Syncthing replicating the same dir to orion + kepler.
{self, ...}: {
  flake.modules.nixos.restic-tofu-state = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.resticTofuState;
    sourceDir = "/home/erik/tofu-state-export";
    repository = "/home/erik/vault/restic/tofu-state"; # vault = sdb, independent of the source disk
  in {
    options.services.resticTofuState = {
      enable = lib.mkEnableOption "restic backup of the tofu-state mirror";

      ntfyUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ntfy topic URL to alert on backup failure (empty = no alert).";
      };
    };

    config = lib.mkIf cfg.enable {
      sops.secrets."restic_tofu_state_password" = {
        sopsFile = self + "/secrets/sops/secrets.yaml";
      };

      # A failed backup (full disk, locked/corrupt repo) is otherwise silent —
      # alert via ntfy. restic has no built-in notifier, so hang it off the
      # systemd unit's OnFailure.
      systemd.services.restic-backups-tofu-state.onFailure =
        lib.mkIf (cfg.ntfyUrl != "") ["restic-tofu-state-onfail.service"];

      systemd.services.restic-tofu-state-onfail = lib.mkIf (cfg.ntfyUrl != "") {
        description = "ntfy alert when the tofu-state restic backup fails";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "restic-tofu-state-onfail" ''
            ${pkgs.curl}/bin/curl -s \
              -H "Title: restic tofu-state backup FAILED" \
              -H "Priority: high" -H "Tags: rotating_light" \
              -d "restic-backups-tofu-state failed on ${config.networking.hostName} — check disk/repo: journalctl -u restic-backups-tofu-state" \
              ${lib.escapeShellArg cfg.ntfyUrl} >/dev/null || true
          '';
        };
      };

      # restic init only creates the leaf repo dir; ensure its parent exists.
      systemd.tmpfiles.rules = [
        "d ${builtins.dirOf repository} 0700 root root - -"
      ];

      services.restic.backups.tofu-state = {
        inherit repository;
        passwordFile = config.sops.secrets."restic_tofu_state_password".path;
        paths = [sourceDir];
        initialize = true;
        timerConfig = {
          OnCalendar = "*-*-* 06:30:00"; # after the 06:00 drift check
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];
      };
    };
  };
}
