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
        dead-man's-switch liveness metric: after each successful backup, write
        restic_tofu_state_last_success_seconds to the node_exporter textfile dir
        (/var/lib/node-exporter-textfile). Grafana alerts on staleness — catches
        a dead timer / failed run that OnFailure can't see. Replaces the old
        Healthchecks ping (declarative, in the metrics pipeline)'';

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

      restRepository = lib.mkEnableOption ''
        an **off-premise** copy to voyager's append-only restic REST server
        (Oracle Always-Free, tailnet-only). The credential-bearing repo URL
        (rest:http://discovery:PASS@voyager:8000/discovery/tofu-state — the path
        MUST start with the REST username, which --private-repos enforces with a
        401) is held in the sops secret `restic_tofu_rest_url` and passed via
        repositoryFile so it never lands in the nix store. Append-only means this job never prunes — a
        compromised sender cannot delete history (retention is server-side /
        manual). Distinct failure domain from the SFTP peer copy'';
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

      # Dead-man's-switch: on success (ExecStartPost runs only on success) write
      # a last-success timestamp to the node_exporter textfile dir. Grafana
      # alerts when it goes stale — catches a dead timer or failed run that
      # OnFailure can't observe. Atomic write (mktemp + mv) so the collector
      # never reads a half-written file. Replaces the old Healthchecks ping.
      systemd.services.restic-backups-tofu-state.serviceConfig.ExecStartPost = lib.mkIf cfg.healthcheck [
        (pkgs.writeShellScript "restic-tofu-state-liveness" ''
          set -eu
          d=/var/lib/node-exporter-textfile
          t=$(${pkgs.coreutils}/bin/date +%s)
          tmp=$(${pkgs.coreutils}/bin/mktemp "$d/.restic_tofu_state.XXXXXX")
          {
            echo "# HELP restic_tofu_state_last_success_seconds Unix time of last successful tofu-state restic backup."
            echo "# TYPE restic_tofu_state_last_success_seconds gauge"
            echo "restic_tofu_state_last_success_seconds $t"
          } > "$tmp"
          # 0644 so the alloy user (textfile collector) can read what root wrote
          # (mktemp creates 0600).
          ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" "$d/restic_tofu_state.prom"
        '')
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

      # Off-premise copy to voyager's append-only restic REST server (Oracle).
      # The only tier outside the house — survives losing the whole building.
      # The full URL (incl. basic-auth password) lives in sops and is read via
      # repositoryFile so it never enters the nix store. No pruneOpts: the
      # server is --append-only, so client-side forget/prune would fail anyway,
      # and refusing to prune is the point (immutable off-site history).
      sops.secrets."restic_tofu_rest_url" = lib.mkIf cfg.restRepository {
        sopsFile = self + "/secrets/sops/secrets.yaml";
        mode = "0400";
      };

      services.restic.backups.tofu-state-rest = lib.mkIf cfg.restRepository {
        repositoryFile = config.sops.secrets."restic_tofu_rest_url".path;
        passwordFile = config.sops.secrets."restic_tofu_state_password".path;
        paths = [sourceDir];
        initialize = true;
        timerConfig = {
          OnCalendar = "*-*-* 07:30:00"; # after the SFTP off-site copy (07:00)
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
      };

      # Monitoring parity with the local + SFTP jobs: the off-PREMISE copy is the
      # one that matters most, so it must not fail silently. Discord on failure +
      # a distinct liveness metric Grafana alerts on when it goes stale/absent.
      systemd.services.restic-backups-tofu-state-rest.onFailure =
        lib.mkIf (cfg.restRepository && cfg.discordWebhookFile != "") ["restic-tofu-state-onfail.service"];

      systemd.services.restic-backups-tofu-state-rest.serviceConfig.ExecStartPost = lib.mkIf (cfg.restRepository && cfg.healthcheck) [
        (pkgs.writeShellScript "restic-tofu-state-rest-liveness" ''
          set -eu
          d=/var/lib/node-exporter-textfile
          t=$(${pkgs.coreutils}/bin/date +%s)
          tmp=$(${pkgs.coreutils}/bin/mktemp "$d/.restic_tofu_state_rest.XXXXXX")
          {
            echo "# HELP restic_tofu_state_rest_last_success_seconds Unix time of last successful off-premise (voyager) tofu-state restic backup."
            echo "# TYPE restic_tofu_state_rest_last_success_seconds gauge"
            echo "restic_tofu_state_rest_last_success_seconds $t"
          } > "$tmp"
          ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" "$d/restic_tofu_state_rest.prom"
        '')
      ];
    };
  };
}
