_: {
  flake.modules.nixos.discovery-kindle-release-agent = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.kindleReleaseAgent;
    runtimeInputs = with pkgs; [
      bash
      cosign
      curl
      docker
      git
      openssh
      openssl
      python3
      skopeo
      systemd
      util-linux
    ];
    agent = pkgs.writeShellApplication {
      name = "kindle-release-agent";
      inherit runtimeInputs;
      text = ''
        exec python3 ${./_kindle-release-agent.py}
      '';
    };
    drillSource = pkgs.runCommand "kindle-release-agent-failure-drill.py" {} ''
      cp ${./_kindle-release-agent.py} "$out"
      substituteInPlace "$out" \
        --replace-fail 'FAIL_AFTER_RECREATE = False' 'FAIL_AFTER_RECREATE = True'
    '';
    drillAgent = pkgs.writeShellApplication {
      name = "kindle-release-agent-failure-drill";
      inherit runtimeInputs;
      text = ''
        exec python3 ${drillSource}
      '';
    };
    unit = executable: {
      after = [
        "docker.service"
        "network-online.target"
        "vault-agent.service"
      ];
      wants = ["network-online.target"];
      requires = ["docker.service" "vault-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = executable;
        TimeoutStartSec = "30min";
        UMask = "0077";
        RuntimeDirectory = "kindle-release-agent";
        RuntimeDirectoryMode = "0700";

        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@mount" "~@reboot" "~@swap"];

        ReadOnlyPaths = [
          "/run/vault-agent"
          "/var/run/docker.sock"
        ];
        ReadWritePaths = [
          "/home/erik/servarr"
          "/run/kindle-release-agent"
          "/run/user/1000"
          "/var/lib/kindle-release-agent"
          "/var/lib/node-exporter-textfile"
        ];
      };
    };
  in {
    options.services.kindleReleaseAgent = {
      enable = lib.mkEnableOption "fixed pull-based Kindle release agent";
      timerEnable = lib.mkEnableOption "hourly Kindle release polling";
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [agent];

      systemd.tmpfiles.rules = [
        "d /var/lib/kindle-release-agent 0700 root root - -"
        "d /var/lib/node-exporter-textfile 0755 root root - -"
      ];

      systemd.services.kindle-release-agent =
        {
          description = "Verify and promote merged Kindle releases";
        }
        // unit "${agent}/bin/kindle-release-agent";

      systemd.services.kindle-release-agent-failure-drill =
        {
          description = "Exercise Kindle post-recreate rollback";
        }
        // unit "${drillAgent}/bin/kindle-release-agent-failure-drill";

      systemd.timers.kindle-release-agent = {
        description = "Hourly merged Kindle release poll";
        wantedBy = lib.optionals cfg.timerEnable ["timers.target"];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5min";
          Unit = "kindle-release-agent.service";
        };
      };
    };
  };
}
