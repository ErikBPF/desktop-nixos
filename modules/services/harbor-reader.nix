{config, ...}: {
  flake.modules.nixos.harbor-reader = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.harborReader;
    registry = "harbor.homelab.pastelariadev.com";
    secretPath = "secret/data/fleet/harbor/readers/${config.networking.hostName}";
    userGroup =
      if cfg.user == null
      then null
      else config.users.users.${cfg.user}.group;
    destination =
      if cfg.format == "docker"
      then "/run/harbor-reader/config.json"
      else "/run/harbor-reader/registries.yaml";
    auth = ''{{ printf "%s:%s" .Data.data.HARBOR_READER_USERNAME .Data.data.HARBOR_READER_SECRET | base64Encode }}'';
    template =
      if cfg.format == "docker"
      then ''
        {{ with secret "${secretPath}" }}
        {"auths":{"${registry}":{"auth":"${auth}"}}}
        {{ end }}
      ''
      else ''
        {{ with secret "${secretPath}" }}
        mirrors:
          docker.io:
            endpoint:
              - "https://${registry}/v2/dockerhub"
              - "https://registry-1.docker.io"
        configs:
          "${registry}":
            auth:
              auth: "${auth}"
        {{ end }}
      '';
  in {
    options.services.harborReader = {
      enable = lib.mkEnableOption "a host-scoped pull-only Harbor credential";
      address = lib.mkOption {
        type = lib.types.str;
        description = "OpenBao address reachable by this host.";
      };
      roleIdFile = lib.mkOption {
        type = lib.types.str;
        description = "AppRole role-id file outside the Nix store.";
      };
      secretIdFile = lib.mkOption {
        type = lib.types.str;
        description = "AppRole secret-id file outside the Nix store.";
      };
      format = lib.mkOption {
        type = lib.types.enum ["docker" "k3s"];
        description = "Runtime registry credential format.";
      };
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User that performs Docker-compatible pulls; null for root-owned k3s auth.";
      };
      authPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Docker-compatible auth symlink consumed by the runtime user.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.format == "k3s" || (cfg.user != null && cfg.authPath != null);
          message = "services.harborReader docker format requires user and authPath";
        }
        {
          assertion = cfg.format == "docker" || (cfg.user == null && cfg.authPath == null);
          message = "services.harborReader k3s format must remain root-owned";
        }
      ];

      systemd.services.harbor-reader = {
        description = "Render this host's Harbor pull credential from OpenBao";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target" "sops-nix.service"];
        wants = ["network-online.target"];
        path = [pkgs.bash];
        serviceConfig =
          {
            Restart = "on-failure";
            RestartSec = "10s";
            RuntimeDirectory = "harbor-reader";
            RuntimeDirectoryMode = "0700";
            Environment = "HOME=/run/harbor-reader";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            ExecStart = "${pkgs.openbao}/bin/bao agent -config=${pkgs.writeText "harbor-reader.hcl" ''
              pid_file = "/run/harbor-reader/agent.pid"
              vault { address = "${cfg.address}" }
              template_config { static_secret_render_interval = "5m" }
              auto_auth {
                method "approle" {
                  mount_path = "auth/approle"
                  config = {
                    role_id_file_path = "${cfg.roleIdFile}"
                    secret_id_file_path = "${cfg.secretIdFile}"
                    remove_secret_id_file_after_reading = false
                  }
                }
              }
              template {
                contents = ${builtins.toJSON template}
                destination = "${destination}"
                perms = "0400"
              }
            ''}";
            ExecStartPost = "${pkgs.bash}/bin/bash -c 'for _ in {1..30}; do [[ -s ${destination} ]] && exit 0; ${pkgs.coreutils}/bin/sleep 1; done; exit 1'";
          }
          // lib.optionalAttrs (cfg.user != null) {
            User = cfg.user;
            Group = userGroup;
          };
      };

      systemd.tmpfiles.rules = lib.optionals (cfg.authPath != null) [
        "d ${builtins.dirOf cfg.authPath} 0700 ${cfg.user} ${userGroup} -"
        "L+ ${cfg.authPath} - - - - /run/harbor-reader/config.json"
      ];
    };
  };
}
