# Platform secrets store — OpenBao (OSS, MPL drop-in for HashiCorp Vault) on
# discovery, the always-on home host. Positioned as a *platform* service (D5 of
# the SSOT/SRP plan): runtime-secret SSOT for home docker (vault-agent), lab k8s
# (ESO), and iac (provider). sops stays the root-of-trust/bootstrap. Lives on
# discovery (not the disposable lab cluster) so tearing down the lab never
# touches secrets. See docs/proposals/2026-06-29-vault-secrets-platform.md (P3)
# and -vault-backup-plan.md (P3.0).
#
# OpenBao over Vault: nixpkgs `vault` is BUSL/unfree; OpenBao is API-compatible.
# StateDirectory=openbao (0700) owns /var/lib/openbao; restartIfChanged=false so
# a rebuild doesn't reseal it. Initialised 2026-06-29 (unseal key + root +
# snapshot token in sops).
{self, ...}: {
  flake.modules.nixos.discovery-vault = {
    pkgs,
    lib,
    ...
  }: let
    addr = "http://127.0.0.1:8200";
    snapDir = "/var/lib/vault-snapshots";
    snapFile = "${snapDir}/openbao.snap";
    textfileDir = "/var/lib/node-exporter-textfile";
    bao = "${pkgs.openbao}/bin/bao";
    jq = "${pkgs.jq}/bin/jq";
    sopsFile = self + "/secrets/sops/secrets.yaml";
  in {
    environment.systemPackages = [pkgs.openbao];

    services.openbao = {
      enable = true;
      settings = {
        ui = true;
        listener.default = {
          type = "tcp";
          address = "127.0.0.1:8200";
          tls_disable = true;
        };
        storage.raft = {
          path = "/var/lib/openbao";
          node_id = "discovery";
        };
        api_addr = "http://127.0.0.1:8200";
        cluster_addr = "http://127.0.0.1:8201";
      };
    };

    sops.secrets."vault_unseal_key" = {
      inherit sopsFile;
      mode = "0400";
    };
    sops.secrets."vault_snapshot_token" = {
      inherit sopsFile;
      mode = "0400";
    };
    sops.secrets."vault_restic_password" = {
      inherit sopsFile;
      mode = "0400";
    };
    # AppRole creds for vault-agent (read-only `discord-read` policy). The
    # secret-id is low-blast-radius (reads only secret/shared/discord) and Bao is
    # loopback-only.
    sops.secrets."vault_agent_role_id" = {
      inherit sopsFile;
      mode = "0400";
    };
    sops.secrets."vault_agent_secret_id" = {
      inherit sopsFile;
      mode = "0400";
    };

    systemd.tmpfiles.rules = ["d ${snapDir} 0700 openbao openbao - -"];

    # vault-agent (P3.2): renders runtime secrets from OpenBao to files under
    # /run/vault-agent so host services consume Vault, not sops. First secret:
    # the Discord webhooks (de-dups the sops copies once consumers cut over).
    # This is the home-side equivalent of ESO in the lab cluster.
    systemd.services.vault-agent = {
      description = "OpenBao agent — render runtime secrets (Discord webhooks) from Vault";
      wantedBy = ["multi-user.target"];
      after = ["openbao-unseal.service"];
      wants = ["openbao-unseal.service"];
      # `bao agent` resolves a token-helper path via `sh` at startup — give it one.
      path = [pkgs.bash];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "10s";
        RuntimeDirectory = "vault-agent";
        RuntimeDirectoryMode = "0755";
        Environment = "HOME=/run/vault-agent";
        ExecStart = "${pkgs.openbao}/bin/bao agent -config=${pkgs.writeText "vault-agent.hcl" ''
          pid_file = "/run/vault-agent/pid"
          vault { address = "${addr}" }
          auto_auth {
            method "approle" {
              mount_path = "auth/approle"
              config = {
                role_id_file_path = "/run/secrets/vault_agent_role_id"
                secret_id_file_path = "/run/secrets/vault_agent_secret_id"
                remove_secret_id_file_after_reading = false
              }
            }
            sink "file" { config = { path = "/run/vault-agent/token" } }
          }
          template {
            contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.incidents }}{{ end }}"
            destination = "/run/vault-agent/discord_webhook_incidents"
            perms = "0444"
          }
          template {
            contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.deploys }}{{ end }}"
            destination = "/run/vault-agent/discord_webhook_deploys"
            perms = "0444"
          }
        ''}";
      };
    };

    # Raft seals on every restart/reboot. Unseal automatically from the
    # sops-held key so an unattended reboot doesn't leave the platform secrets
    # store sealed (and every consumer broken). Semi-auto by design (P3.0): the
    # key lives in sops, so a disk stolen without the age key stays sealed.
    systemd.services.openbao-unseal = {
      description = "Unseal OpenBao on boot (raft seals on restart)";
      wantedBy = ["multi-user.target"];
      after = ["openbao.service"];
      requires = ["openbao.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "openbao-unseal" ''
          export BAO_ADDR=${addr}
          # Wait until the server responds (sealed status still answers).
          for _ in $(seq 1 30); do
            ${bao} status -format=json 2>/dev/null | ${jq} -e 'has("sealed")' >/dev/null 2>&1 && break
            sleep 2
          done
          if ${bao} status -format=json 2>/dev/null | ${jq} -e '.sealed == true' >/dev/null 2>&1; then
            ${bao} operator unseal "$(cat /run/secrets/vault_unseal_key)" >/dev/null
          fi
        '';
      };
    };

    # Backup (P3.0): restic backs up a raft snapshot taken in backupPrepareCommand
    # (consistent online snapshot). Local repo on the vault disk (sdb), separate
    # from the root SSD. The unseal key is NOT here (it's in sops/git) — snapshot
    # and unseal key stay in different trust domains. Off-site to kepler is the
    # immediate follow-up (kepler can't decrypt discovery's sops, so a snapshot
    # there is safe).
    services.restic.backups.vault = {
      repository = "/home/erik/vault/restic/openbao";
      passwordFile = "/run/secrets/vault_restic_password";
      initialize = true;
      paths = [snapFile];
      backupPrepareCommand = ''
        export BAO_ADDR=${addr}
        export BAO_TOKEN="$(cat /run/secrets/vault_snapshot_token)"
        ${bao} operator raft snapshot save ${snapFile}
        ${pkgs.coreutils}/bin/chmod 0600 ${snapFile}
      '';
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };

    # Off-site copy to kepler — DR-mandatory: a backup that only lives on the
    # vault disk dies with discovery. Reuses the `restic-kepler` ssh alias +
    # restic_offsite_ssh_key set up by restic-tofu-state on this host. Backs up
    # the snapshot the local job (03:00) just produced. kepler is NOT a sops
    # recipient for this repo's secrets, so the snapshot there is unreadable
    # without the unseal key (which is not on kepler) — safe off-site.
    services.restic.backups.vault-offsite = {
      repository = "sftp:restic-kepler:/bulk/backups/restic-offsite/openbao";
      passwordFile = "/run/secrets/vault_restic_password";
      initialize = true;
      paths = [snapFile];
      timerConfig = {
        OnCalendar = "*-*-* 03:20:00"; # after the local backup (03:00)
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };

    # Liveness metric on success (P3.0 dead-man's-switch): Grafana alerts when
    # vault_backup_last_success_seconds goes stale/absent. Atomic 0644 write so
    # the alloy textfile collector (non-root) can read it.
    systemd.services.restic-backups-vault.serviceConfig.ExecStartPost = [
      (pkgs.writeShellScript "vault-backup-liveness" ''
        set -eu
        t=$(${pkgs.coreutils}/bin/date +%s)
        tmp=$(${pkgs.coreutils}/bin/mktemp ${textfileDir}/.vault_backup.XXXXXX)
        {
          echo "# HELP vault_backup_last_success_seconds Unix time of last successful openbao raft snapshot backup."
          echo "# TYPE vault_backup_last_success_seconds gauge"
          echo "vault_backup_last_success_seconds $t"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${textfileDir}/vault_backup.prom
      '')
    ];

    # A failed backup is otherwise silent — alert to Discord (off-host).
    systemd.services.restic-backups-vault.onFailure = ["vault-backup-onfail.service"];
    systemd.services.vault-backup-onfail = {
      description = "Discord alert when the OpenBao snapshot backup fails";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "vault-backup-onfail" ''
          ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
            --data "$(${jq} -nc --arg c "🔴 **OpenBao snapshot backup FAILED** on discovery — check: journalctl -u restic-backups-vault" '{content:$c}')" \
            "$(cat /run/secrets/discord_webhook_incidents)" >/dev/null || true
        '';
      };
    };
  };
}
