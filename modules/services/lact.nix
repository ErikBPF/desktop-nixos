_: {
  # LACT — Linux AMDGPU Control Tool.
  # Ships its own systemd unit at $out/lib/systemd/system/lactd.service.
  # We register the package with systemd and only enable the unit; the
  # host-specific config (voltage offset, memory clock, fan curve, power
  # cap) lives next to the host that owns the GPU.
  flake.modules.nixos.lact = {pkgs, ...}: {
    environment.systemPackages = [pkgs.lact];
    systemd.packages = [pkgs.lact];
    # Augment the package-shipped lactd.service (the default overrideStrategy
    # drops in, since the unit comes from the package above). A crashed lactd
    # leaves /run/lactd.sock behind, and the next start aborts with "Socket
    # already exists" → start-limit-hit. Remove any stale socket before start
    # (runs only when the unit is not already active, so a live socket is safe).
    systemd.services.lactd = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStartPre = "-${pkgs.coreutils}/bin/rm -f /run/lactd.sock";
    };
  };
}
