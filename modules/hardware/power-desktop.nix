_: {
  # Always-AC hosts (HTPC/server/workstation). Disables TLP (a laptop
  # battery tuner pulled in by profile-base via m.nixos.power) and pins the
  # CPU frequency governor to performance so AVX2/AVX-512 matmul threads ramp
  # to max turbo immediately. Matches the Orion AI-inference + Kepler ZFS/CUDA
  # workload profile where there is no battery to spare and no idle.
  flake.modules.nixos.power-desktop = {lib, ...}: {
    services.tlp.enable = lib.mkForce false;
    powerManagement.cpuFreqGovernor = lib.mkForce "performance";
    # TLP previously set NMI_WATCHDOG=0 on AC. Disabling TLP took that with
    # it. Free the PMU counter the watchdog consumes (matters for perf /
    # bpftrace sessions on these always-AC hosts) and shave the per-CPU
    # interrupt overhead. Hardware lockup detection still works via the
    # kernel softlockup watchdog on the system tick.
    boot.kernel.sysctl."kernel.nmi_watchdog" = 0;
  };
}
