_: {
  flake.modules.nixos.power = {
    config,
    pkgs,
    ...
  }: {
    services.tlp = {
      enable = true;
      settings = {
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;
        CPU_HWP_DYN_BOOST_ON_AC = 1;
        CPU_HWP_DYN_BOOST_ON_BAT = 0;
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
        PCIE_ASPM_ON_BAT = "powersupersave";
        PCIE_ASPM_ON_AC = "default";
        PLATFORM_PROFILE_ON_AC = "performance";
        PLATFORM_PROFILE_ON_BAT = "low-power";
        START_CHARGE_THRESH_BAT0 = 40;
        STOP_CHARGE_THRESH_BAT0 = 80;
        NMI_WATCHDOG = 0;
      };
    };
    services.acpid.enable = true;

    # --- CPU frequency / throttle profiling ---
    boot.kernelModules = ["msr"];
    environment.systemPackages = [
      config.boot.kernelPackages.turbostat
      config.boot.kernelPackages.cpupower
      config.boot.kernelPackages.perf
      pkgs.msr-tools
      pkgs.s-tui
      pkgs.i7z
    ];
  };
}
