{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.profile-desktop = {...}: {
    imports = [
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
    ];
  };

  flake.modules.home.profile-desktop = {...}: {
    imports = [
      m.home.hyprland
      m.home.hypridle
      m.home.hyprlock
      m.home.hyprpaper
      m.home.quickshell
      m.home.mako
      m.home.rofi
      m.home.wlogout
      m.home.mime
      m.home.fonts
      m.home.theming
      m.home.clipboard
      m.home.ghostty
      m.home.kitty
      m.home.brave
      m.home.vscode
      m.home.packages-desktop
    ];
  };
}
