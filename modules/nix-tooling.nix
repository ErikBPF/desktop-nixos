_: {
  # Fleet-wide Nix ergonomics: nh (nicer rebuild/search CLI) + nix-output-monitor
  # (readable, tree-structured build output; nh auto-detects it).
  #
  # GC is deliberately left to `nix.gc.automatic` (modules/common.nix) — enabling
  # `programs.nh.clean` on top would be a second, competing collector.
  flake.modules.nixos.nix-tooling = {pkgs, ...}: {
    programs.nh.enable = true;
    environment.systemPackages = [pkgs.nix-output-monitor];
  };
}
