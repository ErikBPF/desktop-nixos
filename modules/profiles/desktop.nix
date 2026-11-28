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
      m.nixos.profile-erik

      m.nixos.stylix
      m.nixos.nix-index
      m.nixos.hyprland
      m.nixos.sddm
      m.nixos.fonts
      m.nixos.xdg-portal
      m.nixos.gnome-apps
      m.nixos.audio
      m.nixos.bluetooth
      m.nixos.packages-desktop
    ];
  };

  flake.modules.home.profile-desktop = {...}: {
    imports = [
      # atuin (cross-host shell history) — opt-in, kept off flash-backed headless
      # hosts (archinaut SD / Oracle VMs) whose DB writes wear the storage. The
      # rest of the interactive QoL is fleet-wide via profile-base now.
      m.home.atuin
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
      m.home.github-fork-sync
      m.home.basalt
      m.home.vscode
      m.home.profile-erik
      m.home.buzz
      m.home.tmux
      m.home.grafatui
      m.home.packages-desktop
      m.home.syncthing-tray
    ];
  };
}
