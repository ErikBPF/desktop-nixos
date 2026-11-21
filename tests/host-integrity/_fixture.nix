{output ? "check"}: let
  flake = builtins.getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;
  make = enabled: extraModules:
    lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        [
          flake.modules.nixos.alloy
          ({lib, ...}: {
            options.services.pangolinNewt.enable = lib.mkEnableOption "fixture";
            config = {
              networking.hostName = "integrity-fixture";
              system.stateVersion = "26.05";
              services.hostIntegrity = {
                enable = lib.mkIf enabled true;
                checks = ["store" "signatures" "av"];
                jobs = lib.genAttrs ["store" "signatures" "av"] (check: {
                  scopeId = "fixture-only";
                  paths =
                    if check == "av"
                    then ["/tmp/fixture-scope"]
                    else [];
                  calendar = "weekly";
                  jitterSeconds = 60;
                  timeoutSeconds = 120;
                  retentionDays = 2;
                  maxReceipts = 4;
                  maxFiles = 10;
                  maxRecursion = 2;
                  maxFileBytes = 1024;
                  maxScanBytes = 4096;
                  maxTotalBytes = 8192;
                  outputMaxBytes = 4096;
                  cpuQuotaPercent = 10;
                  memoryMaxBytes = 67108864;
                  ioWeight = 10;
                  nice = 19;
                });
              };
            };
          })
        ]
        ++ extraModules;
    };
  enabled = (make true []).config;
  disabled = (make false []).config;
  invalidChecks = (make true [{services.hostIntegrity.checks = lib.mkForce ["store" "signatures"];}]).config;
  emptyScope = (make true [{services.hostIntegrity.jobs.av.paths = lib.mkForce [];}]).config;
  checkMessage = "Integrity jobs must be configured reporting checks.";
  scopeMessage = "AV requires explicit scope paths; other integrity jobs require an empty path list.";
  invariant = cfg: message: (lib.findFirst (a: a.message == message) (throw "missing integrity assertion") cfg.assertions).assertion;
  alloy = enabled.environment.etc."alloy/config.alloy".text;
in
  assert invariant enabled checkMessage;
  assert invariant enabled scopeMessage;
  assert !(invariant invalidChecks checkMessage);
  assert !(invariant emptyScope scopeMessage);
  assert builtins.hasAttr "jobs" enabled.services.hostIntegrity;
  assert lib.hasInfix ''prometheus.exporter.unix "host_integrity"'' alloy;
  assert lib.hasInfix ''regex         = "host_integrity_.*"'' alloy;
  assert lib.hasInfix ''replacement   = "integrity-fixture"'' alloy;
  assert builtins.elem "d /var/lib/host-integrity 0700 root root - -" enabled.systemd.tmpfiles.rules;
  assert builtins.elem "d /var/lib/host-integrity-metrics 0755 root root - -" enabled.systemd.tmpfiles.rules;
  assert builtins.elem "d /var/lib/node-exporter-textfile 0755 erik users - -" enabled.systemd.tmpfiles.rules;
  assert enabled.systemd.services.host-integrity-report.serviceConfig.User == "root";
  assert lib.all (
    check: let
      unit = enabled.systemd.services."host-integrity-${check}";
      failure = enabled.systemd.services."host-integrity-${check}-failure";
      timer = enabled.systemd.timers."host-integrity-${check}";
    in
      unit.onFailure
      == ["host-integrity-${check}-failure.service"]
      && unit.serviceConfig.TimeoutStartSec == 150
      && unit.environment.TMPDIR == "/run/host-integrity-${check}"
      && unit.serviceConfig.RuntimeDirectoryMode == "0700"
      && unit.serviceConfig.PrivateTmp == (check != "av")
      && unit.serviceConfig.CPUQuota == "10%"
      && unit.serviceConfig.MemoryMax == 67108864
      && unit.serviceConfig.IOWeight == 10
      && unit.serviceConfig.Nice == 19
      && lib.hasInfix "--config" unit.serviceConfig.ExecStart
      && lib.hasInfix "--service-result unit-failed" failure.serviceConfig.ExecStart
      && failure.serviceConfig.TimeoutStartSec == "30s"
      && !(failure.serviceConfig ? ProtectSystem)
      && timer.timerConfig.Persistent
      && timer.timerConfig.RandomizedDelaySec == 60
      && !(disabled.systemd.timers ? "host-integrity-${check}")
  ) ["store" "signatures" "av"];
  assert builtins.elem "d /var/lib/host-integrity/database 0700 root root - -" enabled.systemd.tmpfiles.rules;
  assert !disabled.services.hostIntegrity.enable;
  assert !(disabled.systemd.services ? host-integrity-report);
  assert !(lib.hasInfix ''prometheus.exporter.unix "host_integrity"'' disabled.environment.etc."alloy/config.alloy".text);
    if output == "alloy"
    then alloy
    else "S01_MODULE_EVAL_OK S02_MODULE_EVAL_OK"
