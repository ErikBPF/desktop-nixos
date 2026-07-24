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
{
  self,
  config,
  ...
}: let
  inherit (config) username;
in {
  flake.modules.nixos.discovery-vault = {
    config,
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
    renderedAt = ''# rendered_at={{ timestamp }}\n'';
  in {
    imports = [(import ./_vault-agent.nix {inherit username;})];

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
        # Tailnet listener (P3.1b): lab ESO on kepler reaches the store over the
        # tailnet to repoint off the in-cluster vault. Bound to discovery's
        # tailnet IP (not 0.0.0.0) so it's only on tailscale0; firewalled to
        # tailscale0 below; tailnet ACL default-denies all but kepler→:8200.
        # No TLS: WireGuard already authenticates+encrypts the only transport
        # (see RFC P3.1b TLS decision); revisit in P3.5 hardening.
        listener.tailnet = {
          type = "tcp";
          address = "100.76.140.121:8200";
          tls_disable = true;
        };
        # SWAG reaches the UI/API through a dedicated internal Docker bridge.
        # Only SWAG joins this network; the listener is not exposed to the LAN
        # or the general homelab container network.
        listener.swag_proxy = {
          type = "tcp";
          address = "172.31.82.1:8200";
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

    # Expose 8200 only on the tailnet interface — the global firewall in
    # discovery-networking stays default-closed (8200 not in allowedTCPPorts),
    # so the store is unreachable from the LAN/eno1/br0.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [8200];
    networking.firewall.interfaces.br-openbao.allowedTCPPorts = [8200];

    # The tailnet and SWAG listeners bind addresses created by tailscaled and
    # Docker. A cold boot can race either interface, so retry without a
    # start-limit cap until both exist.
    systemd.services.openbao = {
      after = ["tailscaled.service" "network-online.target"];
      wants = ["network-online.target"];
      startLimitIntervalSec = 0;
      serviceConfig.RestartSec = "2s";
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
    # Off-premise vault backup (RFC 4d): credential-bearing restic REST URL to
    # voyager's append-only server (rest:http://discovery:PASS@voyager:8000/
    # discovery/openbao). Passed via repositoryFile so the password never enters
    # the nix store; the path must start with the REST username (--private-repos).
    sops.secrets."restic_vault_rest_url" = {
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
    # Incidents Discord webhook — sops copy of the value vault-agent renders to
    # /run/vault-agent/discord_webhook_incidents. That render VANISHES exactly
    # when OpenBao is sealed, so the seal-related alert (openbao-unseal-onfail)
    # must read the webhook from sops: the bootstrap trust tier that still works
    # when the runtime secret store is down (D5). Breaks the circular blind spot
    # where the only seal alarm depended on the thing being down.
    sops.secrets."discord_webhook_incidents" = {
      inherit sopsFile;
      mode = "0400";
    };

    systemd.tmpfiles.rules = ["d ${snapDir} 0700 openbao openbao - -"];

    # Guard: vault-offsite reuses the `restic-kepler` SSH alias declared by
    # restic-tofu-state (programs.ssh.extraConfig, gated on its offsiteRepository).
    # That coupling is implicit — if restic-tofu-state is ever disabled the
    # off-site vault backup breaks at runtime, not at eval. Assert the alias is
    # present so it fails loudly instead.
    assertions = [
      {
        assertion = builtins.match ".*Host restic-kepler.*" config.programs.ssh.extraConfig != null;
        message = "discovery-vault: restic-backups-vault-offsite depends on the `restic-kepler` SSH alias, but it is not present in programs.ssh.extraConfig. Enable services.resticTofuState with an offsiteRepository, or declare the alias directly.";
      }
    ];

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
          template_config {
            static_secret_render_interval = "5m"
          }
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
          # Release reporting runs as root and rejects group/world-readable
          # credentials. Keep dedicated copies rather than weakening the
          # existing rootless Compose consumers' access contract.
          template {
            contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.deploys }}{{ end }}"
            destination = "/run/vault-agent/kindle-release-discord-deploys"
            perms = "0600"
          }
          template {
            contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.incidents }}{{ end }}"
            destination = "/run/vault-agent/kindle-release-discord-incidents"
            perms = "0600"
          }
          template {
            contents = "{{ with secret \"secret/data/shared/kindle-release\" }}{\"app_id\":{{ .Data.data.app_id }},\"installation_id\":{{ .Data.data.installation_id }}}{{ end }}"
            destination = "/run/vault-agent/kindle-release-github-app.json"
            perms = "0600"
          }
          template {
            contents = "{{ with secret \"secret/data/shared/kindle-release\" }}{{ .Data.data.private_key_b64 | base64Decode }}{{ end }}"
            destination = "/run/vault-agent/kindle-release-github-app.pem"
            perms = "0600"
          }
          # argus_webhook_hmac: HMAC secret Grafana uses to sign the alert
          # webhook to hermes-argus (contactpoints.yaml hmacConfig). Same value
          # must live in sops hermes_agents/argus_env as
          # WEBHOOK_GRAFANA_ALERTS_SECRET. Renders empty until the key is
          # written to secret/shared/discord (missing keys don't fail render).
          template {
            contents = "${renderedAt}DISCORD_WEBHOOK_INCIDENTS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.incidents }}{{ end }}\nDISCORD_WEBHOOK_DEPLOYS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.deploys }}{{ end }}\nSCRUTINY_NOTIFY_URLS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.scrutiny }}{{ end }}\nWEBHOOK_GRAFANA_ALERTS_SECRET={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.argus_webhook_hmac }}{{ end }}\n"
            destination = "/run/vault-agent/discord.env"
            perms = "0444"
          }
          # P3.3 proof: the tunneling stack's one secret, rendered as a second
          # --env-file for podman-compose-tunneling (orchestration.nix
          # vaultEnvStacks). cloudflared keeps its CLOUDFLARE_TUNNEL_TOKEN
          # interpolation; the value comes from OpenBao (secret/home/tunneling)
          # instead of the sops .env. Restrict the render to the compose user.
          template {
            contents = "${renderedAt}CLOUDFLARE_TUNNEL_TOKEN={{ with secret \"secret/data/home/tunneling\" }}{{ .Data.data.CLOUDFLARE_TUNNEL_TOKEN }}{{ end }}\n"
            destination = "/run/vault-agent/tunneling.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/tunneling.env"]
            }
          }
          # P3.3: monitoring stack-local secrets (grafana/healthchecks/scrutiny).
          # GRAFANA_ADMIN_{USER,PASSWORD} are shared with homepage → in the
          # shared-grafana render above, not here.
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/monitoring\" }}GRAFANA_SECRET_KEY={{ .Data.data.GRAFANA_SECRET_KEY }}\nHEALTHCHECKS_SECRET_KEY={{ .Data.data.HEALTHCHECKS_SECRET_KEY }}\nHEALTHCHECKS_SUPERUSER_PASSWORD={{ .Data.data.HEALTHCHECKS_SUPERUSER_PASSWORD }}\nSCRUTINY_INFLUXDB_PASSWORD={{ .Data.data.SCRUTINY_INFLUXDB_PASSWORD }}\nSCRUTINY_INFLUXDB_TOKEN={{ .Data.data.SCRUTINY_INFLUXDB_TOKEN }}\nTELEGRAM_BOT_TOKEN={{ .Data.data.TELEGRAM_BOT_TOKEN }}\n{{ end }}"
            destination = "/run/vault-agent/monitoring.env"
            perms = "0444"
          }
          # P3.3 shared: DB creds consumed by several stacks (infra/ai-serving/
          # media-server). One render, layered into each consumer via vaultEnvStacks
          # (secret/home/shared-db). POSTGRES_USER stays config in the sops .env.
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/shared-db\" }}POSTGRES_PASSWORD={{ .Data.data.POSTGRES_PASSWORD }}\nREDIS_PASSWORD={{ .Data.data.REDIS_PASSWORD }}\n{{ end }}"
            destination = "/run/vault-agent/shared-db.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/shared-db.env"]
            }
          }
          # P3.3 shared: arr API keys (media + homepage) and grafana admin creds
          # (monitoring + homepage). Each consumer lists these in vaultEnvStacks.
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/shared-arr\" }}RADARR_API_KEY={{ .Data.data.RADARR_API_KEY }}\nSONARR_API_KEY={{ .Data.data.SONARR_API_KEY }}\nLIDARR_API_KEY={{ .Data.data.LIDARR_API_KEY }}\n{{ end }}"
            destination = "/run/vault-agent/shared-arr.env"
            perms = "0444"
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/shared-grafana\" }}GRAFANA_ADMIN_USER={{ .Data.data.GRAFANA_ADMIN_USER }}\nGRAFANA_ADMIN_PASSWORD={{ .Data.data.GRAFANA_ADMIN_PASSWORD }}\n{{ end }}"
            destination = "/run/vault-agent/shared-grafana.env"
            perms = "0444"
          }
          # P3.3 per-stack local secrets (batch 2). Each compose stack keeps its
          # interpolation; values move from the sops .env to these renders.
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/media-server\" }}JELLYSTAT_JWT_SECRET={{ .Data.data.JELLYSTAT_JWT_SECRET }}\n{{ end }}"
            destination = "/run/vault-agent/media-server.env"
            perms = "0444"
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/tools\" }}SEARXNG_SECRET_KEY={{ .Data.data.SEARXNG_SECRET_KEY }}\n{{ end }}"
            destination = "/run/vault-agent/tools.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/tools.env"]
            }
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/media\" }}NORDVPN_USER={{ .Data.data.NORDVPN_USER }}\nNORDVPN_PASSWORD={{ .Data.data.NORDVPN_PASSWORD }}\nQBITTORRENT_USER={{ .Data.data.QBITTORRENT_USER }}\nQBITTORRENT_PASSWORD={{ .Data.data.QBITTORRENT_PASSWORD }}\n{{ end }}"
            destination = "/run/vault-agent/media.env"
            perms = "0444"
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/ai-serving\" }}LITELLM_SALT_KEY={{ .Data.data.LITELLM_SALT_KEY }}\nLANGFUSE_PUBLIC_KEY={{ .Data.data.LANGFUSE_PUBLIC_KEY }}\nLANGFUSE_SECRET_KEY={{ .Data.data.LANGFUSE_SECRET_KEY }}\nLANGFUSE_SALT={{ .Data.data.LANGFUSE_SALT }}\nLANGFUSE_INIT_USER_PASSWORD={{ .Data.data.LANGFUSE_INIT_USER_PASSWORD }}\nOPENCODE_GO_KEY={{ .Data.data.OPENCODE_GO_KEY }}\nUI_PASSWORD={{ .Data.data.UI_PASSWORD }}\nMINIO_ROOT_PASSWORD={{ .Data.data.MINIO_ROOT_PASSWORD }}\nCLICKHOUSE_PASSWORD={{ .Data.data.CLICKHOUSE_PASSWORD }}\n{{ end }}"
            destination = "/run/vault-agent/ai-serving.env"
            perms = "0444"
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/networking\" }}ADGUARD_PASSWORD={{ .Data.data.ADGUARD_PASSWORD }}\nCLOUDFLARE_API_TOKEN={{ .Data.data.CLOUDFLARE_API_TOKEN }}\n{{ end }}"
            destination = "/run/vault-agent/networking.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/networking.env"]
            }
          }
          # Harbor setup and the fixed mirror recipe run as root. Keep the
          # project-scoped robot beside the admin/database inputs without
          # exposing any of them to rootless Compose.
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/harbor\" }}HARBOR_ADMIN_PASSWORD={{ .Data.data.HARBOR_ADMIN_PASSWORD }}\nHARBOR_DB_PASSWORD={{ .Data.data.HARBOR_DB_PASSWORD }}\nHARBOR_ROBOT_USER={{ .Data.data.HARBOR_ROBOT_USER }}\nHARBOR_ROBOT_SECRET={{ .Data.data.HARBOR_ROBOT_SECRET }}\n{{ end }}"
            destination = "/run/vault-agent/harbor.env"
            perms = "0400"
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/ha-harness-litellm\" }}LITELLM_API_KEY={{ .Data.data.LITELLM_API_KEY }}\n{{ end }}{{ with secret \"secret/data/home/ha-harness\" }}HA_HARNESS_TOKEN={{ .Data.data.HA_HARNESS_TOKEN }}\n{{ end }}"
            destination = "/run/vault-agent/ha-harness.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/ha-harness.env"]
            }
          }
          template {
            contents = "${renderedAt}{{ with secret \"secret/data/home/kindle-dash\" }}KINDLE_DASH_CLAUDE_REFRESH_TOKEN={{ .Data.data.KINDLE_DASH_CLAUDE_REFRESH_TOKEN }}\nKINDLE_DASH_CODEX_REFRESH_TOKEN={{ .Data.data.KINDLE_DASH_CODEX_REFRESH_TOKEN }}\nKINDLE_DASH_HA_TOKEN={{ .Data.data.KINDLE_DASH_HA_TOKEN }}\nKINDLE_DASH_OPENCODE_AUTH_COOKIE={{ .Data.data.KINDLE_DASH_OPENCODE_AUTH_COOKIE }}\n{{ end }}"
            destination = "/run/vault-agent/kindle-dash.env"
            perms = "0440"
            exec {
              command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/kindle-dash.env"]
            }
          }
        ''}";
      };
    };

    # Raft seals on every restart/reboot. Unseal automatically from the
    # sops-held key so an unattended reboot doesn't leave the platform secrets
    # store sealed (and every consumer broken). Semi-auto by design (P3.0): the
    # key lives in sops, so a disk stolen without the age key stays sealed.
    systemd.services.openbao-unseal = {
      description = "Ensure OpenBao is unsealed (raft seals on every restart)";
      wantedBy = ["multi-user.target"];
      after = ["openbao.service"];
      # `wants`, NOT `requires`: openbao crash-restarts at boot until its tailnet
      # listener IP appears (see the openbao RestartSec block above). With
      # `requires`, that transient failure CANCELS this oneshot with result
      # `dependency` — and a boot-only oneshot never retries, so the store stays
      # sealed for hours (2026-06-30 / 07-01 / 07-03, and twice on 07-06). `wants`
      # keeps the ordering without the cancel; the script polls seal-status for up
      # to 5 min, so it tolerates openbao coming up late on its own.
      wants = ["openbao.service"];
      # A flapping openbao must never trip a start limit and wedge this dead.
      startLimitIntervalSec = 0;
      # Page (off-host, sops-sourced webhook) only when unseal genuinely fails —
      # openbao unreachable >5 min or the key is rejected. Not on the boot race
      # (the script waits that out). Rate-limited inside the alert script.
      onFailure = ["openbao-unseal-onfail.service"];
      serviceConfig = {
        Type = "oneshot";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        # NOT RemainAfterExit: the timer below re-runs this every minute, so any
        # re-seal (crash, rebuild restart, boot race) self-heals within ~60 s.
        # The script is idempotent — a no-op when the store is already unsealed.
        ExecStart = pkgs.writeShellScript "openbao-unseal" ''
          export BAO_ADDR=${addr}
          # Status checks go through curl, not the bao CLI: during the
          # 2026-07-01 activation the CLI produced no stdout in unit context
          # (jq -e exit 4 = empty input) for 5 straight minutes while curl on
          # the same endpoint succeeded concurrently (seal-probe). seal-status
          # is unauthenticated and answers while sealed. Poll generously — raft
          # log replay after an unclean shutdown outlasted the old 60s window
          # (2026-06-30 boot → sealed ~21h with a green unit).
          status() { ${pkgs.curl}/bin/curl -fsS -m 5 ${addr}/v1/sys/seal-status; }
          for _ in $(seq 1 150); do
            status | ${jq} -e 'has("sealed")' >/dev/null 2>&1 && break
            sleep 2
          done
          if status | ${jq} -e '.sealed == true' >/dev/null 2>&1; then
            # curl, not the bao CLI: the CLI shells out for its token helper
            # and died with `exec: "sh": executable file not found in $PATH`
            # in unit context (2026-07-03 cold boot — store stayed sealed
            # until a manual unseal). /v1/sys/unseal is unauthenticated by
            # design. jq --rawfile keeps the key out of argv/proc; stderr NOT
            # swallowed — an unseal failure must reach the journal.
            ${jq} -n --rawfile k /run/secrets/vault_unseal_key \
              '{key: ($k | rtrimstr("\n"))}' \
              | ${pkgs.curl}/bin/curl -fsS -m 10 -X PUT --data @- \
                  ${addr}/v1/sys/unseal >/dev/null
          fi
          # Fail loudly unless the store is verifiably unsealed — a silent
          # fall-through must show as a red unit, not "Finished".
          status | ${jq} -e '.sealed == false' >/dev/null 2>&1
        '';
      };
    };

    # Re-run the unseal check every minute so ANY re-seal — a crash, a rebuild
    # restart, or the boot tailnet-IP race — self-heals in <=60 s, regardless of
    # why openbao sealed. Boot still gets an immediate run via wantedBy +
    # OnBootSec. The oneshot won't pile up: systemd won't start a second run
    # while one is active.
    systemd.timers.openbao-unseal = {
      description = "Periodically ensure OpenBao is unsealed (self-heal any re-seal)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "1m";
        Persistent = true;
      };
    };

    # Fires (via onFailure) only when auto-unseal genuinely can't recover the
    # store. Reads the webhook from sops, not /run/vault-agent — that render is
    # gone precisely when the store is sealed. Rate-limited to once / 30 min so a
    # prolonged outage doesn't spam the every-minute timer's failures.
    systemd.services.openbao-unseal-onfail = {
      description = "Discord alert when OpenBao auto-unseal fails (store stuck sealed)";
      serviceConfig = {
        Type = "oneshot";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ExecStart = pkgs.writeShellScript "openbao-unseal-onfail" ''
          stamp=/run/openbao-unseal-alert.stamp
          now=$(${pkgs.coreutils}/bin/date +%s)
          if [ -f "$stamp" ] && [ $((now - $(${pkgs.coreutils}/bin/cat "$stamp"))) -lt 1800 ]; then
            exit 0
          fi
          echo "$now" > "$stamp"
          ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
            --data "$(${jq} -nc --arg c "🔴 **OpenBao auto-unseal FAILED** on discovery — the store is sealed and did not self-heal. Every vault-agent consumer (LAN DNS/AdGuard, compose stacks) is down. Check: journalctl -u openbao-unseal" '{content:$c}')" \
            "$(${pkgs.coreutils}/bin/cat /run/secrets/discord_webhook_incidents)" >/dev/null || true
        '';
      };
    };

    # Seal-status probe: the 2026-06-30 incident left the store sealed for ~21h
    # with every consumer (vault-agent renders, lab ESO) silently broken —
    # nothing watched seal state. Write an openbao_sealed gauge to the
    # node_exporter textfile dir every 5 min; Grafana alerts on sealed==1
    # (servarr rules.yaml, uid openbao-sealed). /v1/sys/seal-status is
    # unauthenticated, so no token dependency (it must work exactly when the
    # store is sealed). Probe failure writes sealed=1: unreachable == unusable.
    systemd.services.openbao-seal-probe = {
      description = "Export OpenBao seal status as a node_exporter textfile metric";
      serviceConfig = {
        Type = "oneshot";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ExecStart = pkgs.writeShellScript "openbao-seal-probe" ''
          set -eu
          sealed=$(${pkgs.curl}/bin/curl -fsS -m 10 ${addr}/v1/sys/seal-status \
            | ${jq} -r 'if .sealed then 1 else 0 end' || echo 1)
          d=/var/lib/node-exporter-textfile
          tmp=$(${pkgs.coreutils}/bin/mktemp "$d/.openbao_sealed.XXXXXX")
          {
            echo "# HELP openbao_sealed 1 when the OpenBao store is sealed or unreachable, 0 when unsealed."
            echo "# TYPE openbao_sealed gauge"
            echo "openbao_sealed $sealed"
          } > "$tmp"
          ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" "$d/openbao_sealed.prom"
        '';
      };
    };

    systemd.timers.openbao-seal-probe = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
      };
    };

    # Backup (P3.0): restic backs up a raft snapshot taken in backupPrepareCommand
    # (consistent online snapshot). Local repo on the vault disk (sdb), separate
    # from the root SSD. The unseal key is NOT here (it's in sops/git) — snapshot
    # and unseal key stay in different trust domains. Off-site to kepler is the
    # immediate follow-up (kepler can't decrypt discovery's sops, so a snapshot
    # there is safe).
    services.restic.backups.vault = {
      repository = "/home/${username}/vault/restic/openbao";
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

    # Off-PREMISE copy to voyager's append-only restic REST server (Oracle,
    # tailnet-only) — the only vault snapshot tier outside the house. Backs up
    # the same raft snapshot the local job (03:00) produced. Append-only: no
    # pruneOpts (client-side forget is rejected and refusing to prune is the
    # point — immutable off-site history). URL (incl. basic-auth) lives in sops
    # and is read via repositoryFile so it never enters the nix store. Reuses the
    # `discovery` REST user set up for tofu-state (isolated to /discovery/ via
    # --private-repos). The snapshot is unreadable without the unseal key (not on
    # voyager, not a sops recipient) — safe off-site.
    services.restic.backups.vault-rest = {
      repositoryFile = "/run/secrets/restic_vault_rest_url";
      passwordFile = "/run/secrets/vault_restic_password";
      initialize = true;
      paths = [snapFile];
      timerConfig = {
        OnCalendar = "*-*-* 03:40:00"; # after the SFTP off-site copy (03:20)
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };

    services.restic.backups.vault-b2 = {
      repository = "s3:${config.services.resticTofuState.b2.endpoint}/${config.services.resticTofuState.b2.bucket}/discovery/openbao";
      environmentFile = config.sops.templates."restic-b2.env".path;
      passwordFile = "/run/secrets/vault_restic_password";
      initialize = true;
      paths = [snapFile];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 3"
      ];
    };
    systemd.services.restic-backups-vault-b2.onFailure = ["vault-offsite-backup-onfail.service"];
    systemd.services.restic-backups-vault-b2.serviceConfig.ExecStartPost = [
      (pkgs.writeShellScript "vault-b2-backup-liveness" ''
        set -eu
        t=$(${pkgs.coreutils}/bin/date +%s)
        tmp=$(${pkgs.coreutils}/bin/mktemp ${textfileDir}/.vault_b2_backup.XXXXXX)
        echo "vault_b2_backup_last_success_seconds $t" > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${textfileDir}/vault_b2_backup.prom
      '')
    ];

    # Liveness for the off-premise copy: Grafana alerts when it goes stale.
    systemd.services.restic-backups-vault-rest.serviceConfig.ExecStartPost = [
      (pkgs.writeShellScript "vault-rest-backup-liveness" ''
        set -eu
        t=$(${pkgs.coreutils}/bin/date +%s)
        tmp=$(${pkgs.coreutils}/bin/mktemp ${textfileDir}/.vault_rest_backup.XXXXXX)
        {
          echo "# HELP vault_rest_backup_last_success_seconds Unix time of last successful off-premise (voyager) OpenBao snapshot backup."
          echo "# TYPE vault_rest_backup_last_success_seconds gauge"
          echo "vault_rest_backup_last_success_seconds $t"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${textfileDir}/vault_rest_backup.prom
      '')
    ];
    systemd.services.restic-backups-vault-rest.onFailure = ["vault-offsite-backup-onfail.service"];

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
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ExecStart = pkgs.writeShellScript "vault-backup-onfail" ''
          ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
            --data "$(${jq} -nc --arg c "🔴 **OpenBao snapshot backup FAILED** on discovery — check: journalctl -u restic-backups-vault" '{content:$c}')" \
            "$(cat /run/vault-agent/discord_webhook_incidents)" >/dev/null || true
        '';
      };
    };

    # Off-site liveness metric — mirrors the local job's dead-man's-switch. The
    # local ExecStartPost (above) only proves the 03:00 job ran; a silent SFTP
    # failure of the 03:20 off-site copy would go unnoticed until a DR drill.
    # Separate metric name so Grafana can tell local from off-site staleness.
    systemd.services.restic-backups-vault-offsite.serviceConfig.ExecStartPost = [
      (pkgs.writeShellScript "vault-offsite-backup-liveness" ''
        set -eu
        t=$(${pkgs.coreutils}/bin/date +%s)
        tmp=$(${pkgs.coreutils}/bin/mktemp ${textfileDir}/.vault_offsite_backup.XXXXXX)
        {
          echo "# HELP vault_offsite_backup_last_success_seconds Unix time of last successful OpenBao off-site restic backup."
          echo "# TYPE vault_offsite_backup_last_success_seconds gauge"
          echo "vault_offsite_backup_last_success_seconds $t"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${textfileDir}/vault_offsite_backup.prom
      '')
    ];

    # A failed off-site copy is otherwise silent — alert to Discord (off-host).
    systemd.services.restic-backups-vault-offsite.onFailure = ["vault-offsite-backup-onfail.service"];
    systemd.services.vault-offsite-backup-onfail = {
      description = "Discord alert when the OpenBao off-site snapshot backup fails";
      serviceConfig = {
        Type = "oneshot";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ExecStart = pkgs.writeShellScript "vault-offsite-backup-onfail" ''
          ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
            --data "$(${jq} -nc --arg c "🔴 **OpenBao off-site backup FAILED** on discovery — SFTP to kepler failed; check: journalctl -u restic-backups-vault-offsite" '{content:$c}')" \
            "$(cat /run/vault-agent/discord_webhook_incidents)" >/dev/null || true
        '';
      };
    };
  };
}
