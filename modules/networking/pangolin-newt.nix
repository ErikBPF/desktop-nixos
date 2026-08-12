{
  config,
  self,
  ...
}: let
  inherit (config) email;
  fleet = config.flake.fleet;
in {
  flake.modules.nixos.pangolin-newt = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.pangolinNewt;
    version = "1.15.0";
    newt = pkgs.stdenvNoCC.mkDerivation {
      pname = "newt";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/fosrl/newt/releases/download/${version}/newt_linux_amd64";
        hash = "sha256-JZc9fyZmr1pCbITVJ8E0fKG8Sl3Agb7sioHmJ7r9nb0=";
      };
      dontUnpack = true;
      installPhase = ''
        install -Dm755 "$src" "$out/bin/newt"
      '';
      meta = {
        description = "Pangolin site connector";
        homepage = "https://github.com/fosrl/newt";
        license = lib.licenses.agpl3Only;
        mainProgram = "newt";
        platforms = ["x86_64-linux"];
      };
    };
    blueprint = pkgs.writeText "pangolin-home.yaml" ''
      private-resources:
        home-ingress:
          name: Home ingress
          mode: host
          destination: "${fleet.hosts.discovery.ip}"
          sites:
            - home-discovery
            - home-kepler
          tcp-ports: "443"
          udp-ports: ""
          disable-icmp: true
          alias: "*.${fleet.ingress.homelab.zone}"
          users:
            - ${email}
    '';
    start = pkgs.writeShellApplication {
      name = "pangolin-newt-start";
      runtimeInputs = [newt];
      text = ''
        if [[ ! -s "''${CONFIG_FILE:?}" ]]; then
          export NEWT_PROVISIONING_KEY
          NEWT_PROVISIONING_KEY="$(<"''${CREDENTIALS_DIRECTORY:?}/provisioning-key")"
        fi
        exec newt
      '';
    };
    waitHealthy = pkgs.writeShellApplication {
      name = "pangolin-newt-wait-healthy";
      text = ''
        for _ in {1..30}; do
          [[ -s "''${HEALTH_FILE:?}" ]] && exit 0
          sleep 2
        done
        exit 1
      '';
    };
  in {
    options.services.pangolinNewt = {
      enable = lib.mkEnableOption "Pangolin Cloud Newt site connector";
      siteName = lib.mkOption {
        type = lib.types.enum ["home-discovery" "home-kepler"];
        description = "Stable Pangolin site name.";
      };
    };

    config = lib.mkIf cfg.enable {
      sops.secrets."pangolin/provisioning_key" = {
        sopsFile = self + "/secrets/sops/secrets.yaml";
        mode = "0400";
      };

      modules.upgradeHealthCheck.extraCriticalUnits = ["pangolin-newt.service"];

      systemd.services.pangolin-newt = {
        description = "Pangolin Newt site connector (${cfg.siteName})";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        startLimitIntervalSec = 0;
        environment = {
          PANGOLIN_ENDPOINT = "https://app.pangolin.net";
          NEWT_NAME = cfg.siteName;
          CONFIG_FILE = "/var/lib/pangolin-newt/config.json";
          BLUEPRINT_FILE = blueprint;
          HEALTH_FILE = "/run/pangolin-newt/healthy";
          NEWT_METRICS_PROMETHEUS_ENABLED = "true";
          NEWT_ADMIN_ADDR = "127.0.0.1:2112";
          DISABLE_SSH = "true";
        };
        serviceConfig = {
          ExecStart = lib.getExe start;
          ExecStartPost = lib.getExe waitHealthy;
          Restart = "always";
          RestartSec = "5s";
          TimeoutStartSec = "75s";
          StateDirectory = "pangolin-newt";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "pangolin-newt";
          RuntimeDirectoryMode = "0700";
          LoadCredential = [
            "provisioning-key:${config.sops.secrets."pangolin/provisioning_key".path}"
          ];
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
        };
      };
    };
  };
}
