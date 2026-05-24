_: {
  # LACT — Linux AMDGPU Control Tool.
  # Ships its own systemd unit at $out/lib/systemd/system/lactd.service.
  # We register the package with systemd and only enable the unit; the
  # host-specific config (voltage offset, memory clock, fan curve, power
  # cap) lives next to the host that owns the GPU.
  flake.modules.nixos.lact = {pkgs, ...}: {
    environment.systemPackages = [pkgs.lact];
    systemd.packages = [pkgs.lact];
    systemd.services.lactd.wantedBy = ["multi-user.target"];
  };
}
