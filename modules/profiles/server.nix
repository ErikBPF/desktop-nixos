{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.profile-server = {pkgs, ...}: {
    boot.kernelPackages = pkgs.linuxPackages_7_2;

    imports = [
      m.nixos.headless
      m.nixos.orchestration
    ];
  };
}
