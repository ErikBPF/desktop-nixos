let
  flake = builtins.getFlake (toString ../..);
  base = flake.nixosConfigurations.endeavour;
  collector = (base.extendModules {modules = [{services.hostIntegrity.pilot.enableJobs = lib.mkForce false;}];}).config;
  manual = (base.extendModules {modules = [{services.hostIntegrity.pilot.enableJobs = true;}];}).config;
  scheduled =
    (base.extendModules {
      modules = [
        {
          services.hostIntegrity.pilot = {
            enableJobs = true;
            enableSchedules = true;
          };
        }
      ];
    }).config;
  names = ["signatures" "store" "av"];
  storeCommand = (builtins.fromJSON (builtins.unsafeDiscardStringContext manual.environment.etc."host-integrity/store.json".source.text)).command;
  lib = flake.inputs.nixpkgs.lib;
in
  assert base.config.services.hostIntegrity.pilot.enableJobs;
  assert !base.config.services.hostIntegrity.pilot.enableSchedules;
  assert collector.services.hostIntegrity.enable;
  assert collector.services.hostIntegrity.checks == names;
  assert collector.services.hostIntegrity.jobs == {};
  assert !(collector.systemd.services ? host-integrity-av);
  assert lib.all (check: manual.systemd.timers."host-integrity-${check}".wantedBy == []) names;
  assert lib.all (check: scheduled.systemd.timers."host-integrity-${check}".wantedBy == ["timers.target"]) names;
  assert manual.services.hostIntegrity.jobs.av.paths == ["/home/erik/Downloads"];
  assert manual.services.hostIntegrity.jobs.av.memoryMaxBytes == 2147483648;
  assert manual.services.hostIntegrity.jobs.av.maxTotalBytes == 268435456;
  assert manual.services.hostIntegrity.jobs.av.retentionDays == 30;
  assert manual.services.hostIntegrity.jobs.av.maxReceipts == 128;
  assert manual.systemd.services."host-integrity-av-canary@".serviceConfig.ProtectSystem == manual.systemd.services.host-integrity-av.serviceConfig.ProtectSystem;
  assert manual.systemd.services."host-integrity-av-canary@".serviceConfig.MemoryMax == manual.systemd.services.host-integrity-av.serviceConfig.MemoryMax;
  assert lib.hasInfix "_host-integrity-pilot.py canary" manual.systemd.services."host-integrity-av-canary@".serviceConfig.ExecStart;
  assert builtins.elem "--quiet" storeCommand;
  assert builtins.elemAt storeCommand 2 == "--store";
  assert builtins.elemAt storeCommand 3 == "daemon";
  assert lib.hasInfix "path-info /run/current-system" manual.systemd.services.host-integrity-store-preflight.serviceConfig.ExecStart;
  assert manual.systemd.services.host-integrity-store-preflight.serviceConfig.ProtectSystem == "strict";
  assert lib.hasInfix "--wait 1860" manual.services.restic.backups.endeavour-home.package.text;
  assert lib.hasInfix "/run/host-integrity-coordination/backup.lock" manual.services.restic.backups.endeavour-home.package.text;
  assert builtins.elem "systemd-tmpfiles-setup.service" manual.systemd.services.restic-backups-endeavour-home.after;
  assert manual.systemd.services.restic-backups-endeavour-home.serviceConfig.User == "root";
  assert !(manual.systemd.services.restic-backups-endeavour-home.serviceConfig ? ProtectSystem);
  assert builtins.elem "/run/host-integrity-coordination" manual.systemd.services.host-integrity-av.serviceConfig.ReadWritePaths;
  assert collector.services.restic.backups.endeavour-home.package.outPath != manual.services.restic.backups.endeavour-home.package.outPath; "S04_STAGED_PILOT_EVAL_OK"
