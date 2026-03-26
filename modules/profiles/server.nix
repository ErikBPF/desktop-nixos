{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.profile-server = {...}: {
    imports = [
      m.nixos.headless
      m.nixos.orchestration
    ];
  };
}
