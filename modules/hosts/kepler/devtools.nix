{config, ...}: let
  m = config.flake.modules;
in {
  # Full non-GUI development tool set for ordinary Kepler. Endeavour is the
  # thin client; commands and editors run here. The recovery host keeps the
  # smaller shared kepler-development module for containment.
  flake.modules.nixos.kepler-devtools = _: {
    imports = [m.nixos.profile-erik];
  };

  flake.modules.home.kepler-devtools = {config, ...}: {
    homelab.desktopWorkspaces = {
      enable = false;
      homelabDirectory = "/fast/compute/${config.home.username}/Documents/erik/homelab";
      dataplatformDirectory = "/fast/compute/${config.home.username}/Documents/nstech/dataplatform";
    };

    imports = [
      m.home.profile-erik
      m.home.deepseek-harness
      m.home.desktop-workspaces
    ];
  };
}
