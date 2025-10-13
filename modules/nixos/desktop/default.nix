inputs: {lib, ...}: {
  imports = [
    ./fonts.nix
    ./xdg-portal.nix
    (import ./hyprland.nix inputs)
    ./sddm.nix
  ];

  options.modules.desktop.enable = lib.mkEnableOption "desktop environment (Hyprland + SDDM)";
}
