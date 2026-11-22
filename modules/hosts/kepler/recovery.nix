# Temporary supplemental host; ordinary fleet definitions are not replaced.
_: let
  baseline = builtins.getFlake "github:ErikBPF/desktop-nixos/a3f290e015eacce61e718f8596cdb6acc3716c7c";
  recovery = builtins.getFlake "github:ErikBPF/desktop-nixos/228bc67bf427fa1c4d33508f3f5967e2b1008d7a";
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
