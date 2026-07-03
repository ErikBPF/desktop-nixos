{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.profile-desktop = {...}: {
    imports = [
      # moved out of profile-base: GUI/workstation-only concerns
      m.nixos.xserver
      m.nixos.peripherals
      m.nixos.power
      m.nixos.thunderbolt
      m.nixos.vms
      m.nixos.containers
      m.nixos.file-systems

      m.nixos.laptop-hermes-client
      m.nixos.laptop-opencode-client
      m.nixos.stylix
      m.nixos.nix-index
      m.nixos.hyprland
      m.nixos.sddm
      m.nixos.fonts
      m.nixos.xdg-portal
      m.nixos.audio
      m.nixos.bluetooth
      m.nixos.packages-desktop
      m.nixos.dev-dotnet
      m.nixos.dev-go
      m.nixos.dev-java
      m.nixos.dev-javascript
      m.nixos.dev-python
      m.nixos.dev-paths
      m.nixos.dev-nix-ld
      m.nixos.firefox-policies
    ];
  };

  flake.modules.home.profile-desktop = {...}: {
    imports = [
      m.home.hyprland
      m.home.hypridle
      m.home.hyprlock
      m.home.quickshell
      m.home.mako
      m.home.easyeffects
      m.home.rofi
      m.home.wlogout
      m.home.stylix
      m.home.udiskie
      m.home.mime
      m.home.yazi-desktop
      m.home.fonts
      m.home.theming
      m.home.clipboard
      m.home.ghostty
      m.home.kitty
      m.home.brave
      m.home.firefox
      m.home.obsidian
      m.home.obsidian-sync
      m.home.vscode
      m.home.nvim
      m.home.claude-code
      m.home.codex
      m.home.opencode
      m.home.hermes-agent
      m.home.packages-desktop
      m.home.syncthing-tray
    ];
  };
}
