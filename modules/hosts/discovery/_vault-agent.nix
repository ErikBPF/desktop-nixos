{username}: {
  lib,
  pkgs,
  ...
}: let
  addr = "http://127.0.0.1:8200";
in {
  users.groups.vault-consumers = {};
  users.users.${username}.extraGroups = ["vault-consumers"];

  systemd.services.vault-agent = lib.mkForce {
    description = "OpenBao agent — render runtime secrets from Vault";
    wantedBy = ["multi-user.target"];
    after = ["openbao-unseal.service"];
    wants = ["openbao-unseal.service"];
    path = [pkgs.bash];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
      Group = "vault-consumers";
      RuntimeDirectory = "vault-agent";
      RuntimeDirectoryMode = "0750";
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
          sink "file" { config = { path = "/run/vault-agent/token", mode = 0640 } }
        }
        template {
          contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.incidents }}{{ end }}"
          destination = "/run/vault-agent/discord_webhook_incidents"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.deploys }}{{ end }}"
          destination = "/run/vault-agent/discord_webhook_deploys"
          perms = "0440"
        }
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
        template {
          contents = "DISCORD_WEBHOOK_INCIDENTS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.incidents }}{{ end }}\nDISCORD_WEBHOOK_DEPLOYS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.deploys }}{{ end }}\nSCRUTINY_NOTIFY_URLS={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.scrutiny }}{{ end }}\nWEBHOOK_GRAFANA_ALERTS_SECRET={{ with secret \"secret/data/shared/discord\" }}{{ .Data.data.argus_webhook_hmac }}{{ end }}\n"
          destination = "/run/vault-agent/discord.env"
          perms = "0440"
        }
        template {
          contents = "CLOUDFLARE_TUNNEL_TOKEN={{ with secret \"secret/data/home/tunneling\" }}{{ .Data.data.CLOUDFLARE_TUNNEL_TOKEN }}{{ end }}\n"
          destination = "/run/vault-agent/tunneling.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/monitoring\" }}GRAFANA_SECRET_KEY={{ .Data.data.GRAFANA_SECRET_KEY }}\nHEALTHCHECKS_SECRET_KEY={{ .Data.data.HEALTHCHECKS_SECRET_KEY }}\nHEALTHCHECKS_SUPERUSER_PASSWORD={{ .Data.data.HEALTHCHECKS_SUPERUSER_PASSWORD }}\nSCRUTINY_INFLUXDB_PASSWORD={{ .Data.data.SCRUTINY_INFLUXDB_PASSWORD }}\nSCRUTINY_INFLUXDB_TOKEN={{ .Data.data.SCRUTINY_INFLUXDB_TOKEN }}\nTELEGRAM_BOT_TOKEN={{ .Data.data.TELEGRAM_BOT_TOKEN }}\n{{ end }}"
          destination = "/run/vault-agent/monitoring.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/shared-db\" }}POSTGRES_PASSWORD={{ .Data.data.POSTGRES_PASSWORD }}\nREDIS_PASSWORD={{ .Data.data.REDIS_PASSWORD }}\n{{ end }}"
          destination = "/run/vault-agent/shared-db.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/shared-arr\" }}RADARR_API_KEY={{ .Data.data.RADARR_API_KEY }}\nSONARR_API_KEY={{ .Data.data.SONARR_API_KEY }}\nLIDARR_API_KEY={{ .Data.data.LIDARR_API_KEY }}\n{{ end }}"
          destination = "/run/vault-agent/shared-arr.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/shared-grafana\" }}GRAFANA_ADMIN_USER={{ .Data.data.GRAFANA_ADMIN_USER }}\nGRAFANA_ADMIN_PASSWORD={{ .Data.data.GRAFANA_ADMIN_PASSWORD }}\n{{ end }}"
          destination = "/run/vault-agent/shared-grafana.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/media-server\" }}JELLYSTAT_JWT_SECRET={{ .Data.data.JELLYSTAT_JWT_SECRET }}\n{{ end }}"
          destination = "/run/vault-agent/media-server.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/tools\" }}SEARXNG_SECRET_KEY={{ .Data.data.SEARXNG_SECRET_KEY }}\n{{ end }}"
          destination = "/run/vault-agent/tools.env"
          perms = "0440"
          exec {
            command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/tools.env"]
          }
        }
        template {
          contents = "{{ with secret \"secret/data/home/media\" }}NORDVPN_USER={{ .Data.data.NORDVPN_USER }}\nNORDVPN_PASSWORD={{ .Data.data.NORDVPN_PASSWORD }}\nQBITTORRENT_USER={{ .Data.data.QBITTORRENT_USER }}\nQBITTORRENT_PASSWORD={{ .Data.data.QBITTORRENT_PASSWORD }}\n{{ end }}"
          destination = "/run/vault-agent/media.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/ai-serving\" }}LITELLM_SALT_KEY={{ .Data.data.LITELLM_SALT_KEY }}\nLANGFUSE_PUBLIC_KEY={{ .Data.data.LANGFUSE_PUBLIC_KEY }}\nLANGFUSE_SECRET_KEY={{ .Data.data.LANGFUSE_SECRET_KEY }}\nLANGFUSE_SALT={{ .Data.data.LANGFUSE_SALT }}\nLANGFUSE_INIT_USER_PASSWORD={{ .Data.data.LANGFUSE_INIT_USER_PASSWORD }}\nOPENCODE_GO_KEY={{ .Data.data.OPENCODE_GO_KEY }}\nUI_PASSWORD={{ .Data.data.UI_PASSWORD }}\nMINIO_ROOT_PASSWORD={{ .Data.data.MINIO_ROOT_PASSWORD }}\nCLICKHOUSE_PASSWORD={{ .Data.data.CLICKHOUSE_PASSWORD }}\n{{ end }}"
          destination = "/run/vault-agent/ai-serving.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/networking\" }}ADGUARD_PASSWORD={{ .Data.data.ADGUARD_PASSWORD }}\nCLOUDFLARE_API_TOKEN={{ .Data.data.CLOUDFLARE_API_TOKEN }}\n{{ end }}"
          destination = "/run/vault-agent/networking.env"
          perms = "0440"
        }
        template {
          contents = "{{ with secret \"secret/data/home/harbor\" }}HARBOR_ADMIN_PASSWORD={{ .Data.data.HARBOR_ADMIN_PASSWORD }}\nHARBOR_DB_PASSWORD={{ .Data.data.HARBOR_DB_PASSWORD }}\nHARBOR_ROBOT_USER={{ .Data.data.HARBOR_ROBOT_USER }}\nHARBOR_ROBOT_SECRET={{ .Data.data.HARBOR_ROBOT_SECRET }}\n{{ end }}"
          destination = "/run/vault-agent/harbor.env"
          perms = "0400"
        }
        template {
          contents = "{{ with secret \"secret/data/home/ha-harness-litellm\" }}LITELLM_API_KEY={{ .Data.data.LITELLM_API_KEY }}\n{{ end }}{{ with secret \"secret/data/home/ha-harness\" }}HA_HARNESS_TOKEN={{ .Data.data.HA_HARNESS_TOKEN }}\n{{ end }}"
          destination = "/run/vault-agent/ha-harness.env"
          perms = "0440"
          exec {
            command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/ha-harness.env"]
          }
        }
        template {
          contents = "{{ with secret \"secret/data/home/kindle-dash\" }}KINDLE_DASH_CLAUDE_REFRESH_TOKEN={{ .Data.data.KINDLE_DASH_CLAUDE_REFRESH_TOKEN }}\nKINDLE_DASH_CODEX_REFRESH_TOKEN={{ .Data.data.KINDLE_DASH_CODEX_REFRESH_TOKEN }}\nKINDLE_DASH_HA_TOKEN={{ .Data.data.KINDLE_DASH_HA_TOKEN }}\nKINDLE_DASH_OPENCODE_AUTH_COOKIE={{ .Data.data.KINDLE_DASH_OPENCODE_AUTH_COOKIE }}\n{{ end }}"
          destination = "/run/vault-agent/kindle-dash.env"
          perms = "0440"
          exec {
            command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/kindle-dash.env"]
          }
        }
      ''}";
    };
  };
}
