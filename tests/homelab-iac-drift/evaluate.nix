let
  flake = builtins.getFlake (toString ../..);
  c = flake.nixosConfigurations.discovery.config;
  lib = flake.inputs.nixpkgs.lib;
  unit = c.systemd.services.homelab-iac-drift;
  alloy = c.environment.etc."alloy/config.alloy".text;
in
  assert unit.serviceConfig.TimeoutStartSec == 3600;
  assert unit.serviceConfig.TimeoutStopSec == "30s";
  assert unit.serviceConfig.SuccessExitStatus == [2];
  assert lib.hasPrefix "+" unit.serviceConfig.ExecStartPre;
  assert lib.hasInfix "timeout --signal=KILL 30s " unit.serviceConfig.ExecStartPre;
  assert lib.hasInfix "timeout --signal=KILL 30s " unit.serviceConfig.ExecStopPost;
  assert lib.hasInfix " begin " unit.serviceConfig.ExecStartPre;
  assert lib.hasPrefix "+" unit.serviceConfig.ExecStopPost;
  assert lib.hasInfix " finish " unit.serviceConfig.ExecStopPost;
  assert lib.hasInfix ''flock -w 900 -E 75 "$CACHE_DIRECTORY/run.lock"'' unit.serviceConfig.ExecStart.text;
  assert lib.hasInfix ''flock -w 900 -E 75 "$CACHE_DIRECTORY/run.lock"'' c.systemd.services.homelab-iac-main-apply.serviceConfig.ExecStart.text;
  assert builtins.elem "d /var/lib/homelab-iac-drift-metrics 0755 root root - -" c.systemd.tmpfiles.rules;
  assert lib.hasInfix ''replacement = "discovery"'' alloy;
  assert lib.hasInfix ''host_integrity_.*|homelab_iac_drift_.*'' alloy; {
    check = "S09_MODULE_EVAL_OK";
    inherit alloy;
    reporters = [unit.serviceConfig.ExecStartPre unit.serviceConfig.ExecStopPost];
  }
