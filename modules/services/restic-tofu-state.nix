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

      discordWebhookFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to a file holding the Discord webhook URL to alert on backup failure (read at runtime; empty = no alert).";
      };

      healthcheck = lib.mkEnableOption ''
        Healthchecks dead-man's-switch: ping after each successful backup so
        Healthchecks alerts if the ping stops (dead timer / down host, which
        OnFailure can't see). The ping URL is read at runtime from the sops
        secret restic_tofu_state_hc_url'';

      offsiteRepository = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          restic SFTP repo URL for an off-machine copy (empty = off), e.g.
          "sftp:restic-offsite@kepler:/bulk/backups/restic-offsite/tofu-state".
          Connects with the sops-held restic_offsite_ssh_key as the dedicated
          restic-offsite user (see restic-offsite-target.nix on the peer).
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      sops.secrets."restic_tofu_state_password" = {
        sopsFile = self + "/secrets/sops/secrets.yaml";
      };

      # A failed backup (full disk, locked/corrupt repo) is otherwise silent —
      # alert to Discord. restic has no built-in notifier, so hang it off the
      # systemd unit's OnFailure. Discord (off-host) is used over ntfy because
      # ntfy on discovery rides SWAG and wouldn't survive an ingress outage.
      systemd.services.restic-backups-tofu-state.onFailure =
        lib.mkIf (cfg.discordWebhookFile != "") ["restic-tofu-state-onfail.service"];

      systemd.services.restic-tofu-state-onfail = lib.mkIf (cfg.discordWebhookFile != "") {
        description = "Discord alert when the tofu-state restic backup fails";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "restic-tofu-state-onfail" ''
            ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
              --data "$(${pkgs.jq}/bin/jq -nc --arg c "🔴 **restic tofu-state backup FAILED** on ${config.networking.hostName} — check disk/repo: \`journalctl -u restic-backups-tofu-state\`" '{content:$c}')" \
              "$(cat ${lib.escapeShellArg cfg.discordWebhookFile})" >/dev/null || true
          '';
        };
      };

      # Dead-man's-switch: ping Healthchecks after a successful backup
      # (ExecStartPost runs only on success). A missed ping ⇒ backup failed,
      # timer dead, or host down. The URL is a capability, so it lives in sops
      # and is read at runtime rather than baked into the unit.
      sops.secrets."restic_tofu_state_hc_url" = lib.mkIf cfg.healthcheck {
        sopsFile = self + "/secrets/sops/secrets.yaml";
      };
      systemd.services.restic-backups-tofu-state.serviceConfig.ExecStartPost = lib.mkIf cfg.healthcheck [
        "${pkgs.bash}/bin/bash -c '${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 -o /dev/null \"$(cat ${config.sops.secrets."restic_tofu_state_hc_url".path})\"'"
      ];

      # restic init only creates the leaf repo dir; ensure its parent exists.
      # The off-site path also needs /root/.ssh for the accept-new known_hosts.
      systemd.tmpfiles.rules =
        ["d ${builtins.dirOf repository} 0700 root root - -"]
        ++ lib.optionals (cfg.offsiteRepository != "") [
          "d /root/.ssh 0700 root root - -"
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

      # Off-site copy over SFTP to a peer's restic-offsite user. Same encrypted
      # data, a different machine — the only tier that survives losing discovery.
      sops.secrets."restic_offsite_ssh_key" = lib.mkIf (cfg.offsiteRepository != "") {
        sopsFile = self + "/secrets/sops/secrets.yaml";
        mode = "0400";
      };

      # Connection details live in root's ssh config (not restic extraOptions —
      # the restic module shell-splits those, breaking a multi-word
      # sftp.command). Repo URL uses the `restic-kepler` alias below.
      programs.ssh.extraConfig = lib.mkIf (cfg.offsiteRepository != "") ''
        Host restic-kepler
          HostName kepler
          Port 2222
          User restic-offsite
          IdentityFile ${config.sops.secrets."restic_offsite_ssh_key".path}
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile /root/.ssh/known_hosts
      '';

      services.restic.backups.tofu-state-offsite = lib.mkIf (cfg.offsiteRepository != "") {
        repository = cfg.offsiteRepository;
        passwordFile = config.sops.secrets."restic_tofu_state_password".path;
        paths = [sourceDir];
        initialize = true;
        timerConfig = {
          OnCalendar = "*-*-* 07:00:00"; # after the local backup (06:30)
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
