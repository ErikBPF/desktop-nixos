{config, ...}: let
  m = config.flake.modules;
in {
  # Full non-GUI development tool set for ordinary Kepler. Endeavour is the
  # thin client; commands and editors run here. The recovery host keeps the
  # smaller shared kepler-development module for containment.
  flake.modules.nixos.kepler-devtools = {pkgs, ...}: {
    imports = [
      m.nixos.dev-python
      m.nixos.dev-javascript
      m.nixos.dev-go
      m.nixos.dev-java
      m.nixos.dev-dotnet
      m.nixos.dev-paths
      m.nixos.dev-nix-ld
      m.nixos.opencode-client
      m.nixos.hermes-client
    ];

    environment.systemPackages = with pkgs; [
      nvtopPackages.full # GPU monitoring for btop/nvtop
      zellij
    ];
  };

  flake.modules.home.kepler-devtools = {config, ...}: {
    homelab.desktopWorkspaces = {
      enable = false;
      homelabDirectory = "/fast/compute/${config.home.username}/Documents/erik/homelab";
      dataplatformDirectory = "/fast/compute/${config.home.username}/Documents/nstech/dataplatform";
    };

    imports = [
      m.home.nvim
      m.home.codex
      m.home.opencode
      m.home.desktop-workspaces
      m.home.claude-code
      m.home.goose
      m.home.herdr
      m.home.tuicr
      m.home.hermes-agent
      m.home.pi
      m.home.deepseek-harness
    ];
  };
}
