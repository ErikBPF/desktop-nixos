_: {
  flake.modules.nixos.kepler-wazuh-manager-capture = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.wazuhManagerCapture;
    token = "/run/wazuh-manager-scale/token";
    command = mode: "${pkgs.python3}/bin/python3 ${./_wazuh-manager-capture.py} ${mode} --token-file ${token} --ca-file ${cfg.clusterCaFile} --transport-revision ${cfg.transportRevision} --transport-sha256 ${cfg.transportSha256}";
    service = mode: {
      after = ["network-online.target" "wazuh-manager-scale-credential.service"];
      wants = ["network-online.target"];
      requires = ["wazuh-manager-scale-credential.service"];
      unitConfig.RequiresMountsFor = ["/fast" "/bulk"];
      path = [pkgs.zfs pkgs.gnutar pkgs.openssl pkgs.systemd pkgs.docker-client];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = command mode;
        User = "root";
        UMask = "0077";
        StateDirectory = "wazuh-manager-capture";
        StateDirectoryMode = "0700";
        TimeoutStartSec =
          if mode == "capture"
          then "40min"
          else "150s";
        TimeoutStopSec = "5s";
        KillMode = "control-group";
        CPUQuota = "100%";
        MemoryMax = "512M";
        Nice = 15;
        IOSchedulingClass = "idle";
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  in {
    options.services.wazuhManagerCapture = {
      enable = lib.mkEnableOption "bounded Kepler Wazuh manager database capture";
      transportRevision = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "1c0dfb0d8e664be099485d48ed38a3ef5158da4d";
        description = "Reviewed, published private Servarr transport revision; operator materializes it outside the Nix store.";
      };
      transportSha256 = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "405be8c85afcf25553fb09a83ae96340a5913ff510b64d0fbb7dc11a901df4c4";
        description = "SHA256 of the exact published self-contained transport script.";
      };
      schedule = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Reviewed daily calendar; null keeps capture manual while recovery remains armed.";
      };
      vaultAddress = lib.mkOption {
        type = lib.types.str;
        description = "Sanctioned OpenBao endpoint for the dedicated reader.";
      };
      roleIdFile = lib.mkOption {
        type = lib.types.str;
        description = "Dedicated root-only AppRole bootstrap file outside the Nix store.";
      };
      secretIdFile = lib.mkOption {
        type = lib.types.str;
        description = "Dedicated root-only AppRole SecretID file outside the Nix store.";
      };
      clusterCaFile = lib.mkOption {
        type = lib.types.path;
        description = "Authenticated public Kubernetes API CA; never an admin kubeconfig.";
      };
    };
    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.python3];
      assertions = [
        {
          assertion = config.networking.hostName == "kepler";
          message = "Wazuh capture owns only Kepler's reviewed PVC backing dataset.";
        }
      ];
      systemd.tmpfiles.rules = [
        "d /bulk/backups/wazuh 0700 root root -"
        "d /bulk/backups/wazuh/managers 0700 root root -"
        "d /bulk/k8s/wazuh-recovery-proof 0755 root root -"
      ];
      systemd.services.wazuh-manager-scale-credential = {
        after = ["network-online.target" "sops-nix.service" "tailscaled-autoconnect.service"];
        wants = ["network-online.target" "tailscaled-autoconnect.service"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "10s";
          RuntimeDirectory = "wazuh-manager-scale";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "restart";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ExecStart = "${pkgs.openbao}/bin/bao agent -config=${pkgs.writeText "wazuh-manager-scale.hcl" ''
            vault { address = "${cfg.vaultAddress}" }
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
              contents = "{{ with secret \"secret/data/fleet/wazuh/manager-scale/kepler\" }}{{ .Data.data.token }}{{ end }}"
              destination = "${token}"
              perms = "0600"
            }
          ''}";
          ExecStartPost = "${pkgs.bash}/bin/bash -c 'for _ in {1..60}; do [[ -s ${token} ]] && exit 0; ${pkgs.coreutils}/bin/sleep 1; done; exit 1'";
          TimeoutStartSec = "70s";
        };
      };
      systemd.services.wazuh-manager-capture =
        (service "capture")
        // {
          onFailure = ["wazuh-manager-capture-recovery.service"];
        };
      systemd.services.wazuh-manager-capture-recovery =
        (service "recover")
        // {
          wantedBy = ["multi-user.target"];
        };
      systemd.services.wazuh-manager-capture-rescue = service "rescue";
      systemd.timers.wazuh-manager-capture-rescue = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
          AccuracySec = "1s";
        };
      };
      systemd.timers.wazuh-manager-capture = lib.mkIf (cfg.schedule != null) {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = false;
        };
      };
    };
  };
}
