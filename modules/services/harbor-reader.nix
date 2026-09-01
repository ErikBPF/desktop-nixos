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
    };

    config = lib.mkIf cfg.enable {
      systemd.services.harbor-reader = {
        description = "Render this host's Harbor pull credential from OpenBao";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target" "sops-nix.service"];
        wants = ["network-online.target"];
        path = [pkgs.bash];
        serviceConfig = {
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
        };
      };

      systemd.tmpfiles.rules = lib.optionals (cfg.format == "docker") [
        "d /root/.docker 0700 root root -"
        "L+ /root/.docker/config.json - - - - /run/harbor-reader/config.json"
      ];
    };
  };
}
