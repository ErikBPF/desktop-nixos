_: {
  flake.modules.nixos.endeavour-host-integrity = {
    config,
    lib,
    pkgs,
    ...
  }: let
    pilot = config.services.hostIntegrity.pilot;
    coordination = "/run/host-integrity-coordination/backup.lock";
    common = {
      coordinationLock = coordination;
      paths = [];
      jitterSeconds = 900;
      retentionDays = 30;
      maxReceipts = 128;
      maxFiles = 2000;
      maxRecursion = 8;
      maxFileBytes = 67108864;
      maxScanBytes = 134217728;
      maxTotalBytes = 268435456;
      outputMaxBytes = 262144;
      cpuQuotaPercent = 25;
      ioWeight = 10;
      nice = 19;
    };
  in {
    options.services.hostIntegrity.pilot = {
      enableJobs = lib.mkEnableOption "manually started Endeavour integrity jobs after collector enrollment";
      enableSchedules = lib.mkEnableOption "scheduled Endeavour integrity observation after controlled drills";
    };
    config = {
      assertions = [
        {
          assertion = !pilot.enableSchedules || pilot.enableJobs;
          message = "Integrity observation schedules require the reviewed jobs stage.";
        }
      ];
      services.hostIntegrity = {
        enable = true;
        checks = ["signatures" "store" "av"];
        jobs = lib.optionalAttrs pilot.enableJobs {
          signatures =
            common
            // {
              scopeId = "endeavour-standard-definitions-v1";
              calendar = "*-*-* 03:10:00";
              timeoutSeconds = 900;
              memoryMaxBytes = 805306368;
            };
          store =
            common
            // {
              scopeId = "endeavour-store-contents-v1";
              calendar = "*-*-* 03:40:00";
              timeoutSeconds = 1800;
              memoryMaxBytes = 536870912;
            };
          av =
            common
            // {
              scopeId = "endeavour-downloads-bounded-v1";
              paths = ["/home/erik/Downloads"];
              calendar = "Sun *-*-* 04:40:00";
              timeoutSeconds = 900;
              memoryMaxBytes = 2147483648;
            };
        };
      };
      systemd.tmpfiles.rules = lib.mkIf pilot.enableJobs [
        "d /run/host-integrity-coordination 0700 root root - -"
        "f ${coordination} 0600 root root - -"
      ];
      systemd.services.restic-backups-endeavour-home.after = lib.mkIf pilot.enableJobs (lib.mkAfter ["systemd-tmpfiles-setup.service"]);
      services.restic.backups.endeavour-home.package = lib.mkIf pilot.enableJobs (pkgs.writeShellScriptBin "restic" ''
        exec ${pkgs.util-linux}/bin/flock --exclusive --wait 1860 --conflict-exit-code 75 ${coordination} ${pkgs.restic}/bin/restic "$@"
      '');
      systemd.timers =
        lib.mkIf (pilot.enableJobs && !pilot.enableSchedules)
        (lib.genAttrs ["host-integrity-signatures" "host-integrity-store" "host-integrity-av"] (_: {
          wantedBy = lib.mkForce [];
        }));
    };
  };
}
