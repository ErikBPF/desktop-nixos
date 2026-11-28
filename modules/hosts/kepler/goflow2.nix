{config, ...}: let
  keplerIp = config.fleet.hosts.kepler.ip;
in {
  flake.modules.nixos.kepler-goflow2 = {
    lib,
    pkgs,
    ...
  }: {
    # IPFIX v10 collector for the UDM LAN gateway. goflow2's `netflow://`
    # scheme decodes NetFlow v5/v9 and IPFIX v10; this deployment accepts
    # only the gateway source (enforced in kepler-networking's iptables chain).
    # Flow records are discarded (`/dev/null`): the collector exists for its
    # Prometheus counters, and raw retention would need nfdump or a log sink.
    systemd.services.goflow2 = {
      description = "goflow2 IPFIX collector for the UDM LAN gateway";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.goflow2}/bin/goflow2"
          "-listen=netflow://${keplerIp}:2055?workers=2&queue_size=50000"
          "-addr=127.0.0.1:8081"
          "-transport=file"
          "-transport.file=/dev/null"
          "-loglevel=info"
        ];
        Restart = "always";
        RestartSec = 5;

        # Bounded footprint: one gateway's sampling rate is a trickle, but
        # the receiver queue and Go heap must never grow into the host budget.
        MemoryHigh = "192M";
        MemoryMax = "256M";
        CPUQuota = "50%";
        TasksMax = 64;
        LimitNOFILE = 4096;

        # No state on disk, no privileges, no writable paths.
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "goflow2";
      };
    };
  };
}
