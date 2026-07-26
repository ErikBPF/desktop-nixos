{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.work = {...}: {
    imports = [
      m.nixos.kace-agent
      m.nixos.trend-agent
      m.nixos.cloudflare-warp
    ];
  };
}
