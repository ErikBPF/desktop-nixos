# Temporary supplemental host; ordinary fleet definitions are not replaced.
{inputs, ...}: let
  baseline = inputs.kepler-recovery-baseline;
  recovery = inputs.kepler-recovery-guest;
in {
  flake.nixosConfigurations.kepler-cp1-recovery = baseline.nixosConfigurations.kepler.extendModules {
    modules = [
      ({lib, ...}: {
        microvm.vms.cp-1.evaluatedConfig = recovery.nixosConfigurations.kepler.config.microvm.vms.cp-1.config;
        # Never fall back automatically to a host that reinstalls the old member.
        boot.loader.systemd-boot.bootCounting.enable = lib.mkForce false;
      })
    ];
  };
}
