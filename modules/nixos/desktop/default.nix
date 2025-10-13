inputs: {
  config,
  lib,
  ...
}: {
  options.modules.desktop.enable = lib.mkEnableOption "desktop environment (Hyprland + SDDM)";

  config = lib.mkIf config.modules.desktop.enable {
    imports = [
      ./fonts.nix
      ./xdg-portal.nix
      (import ./hyprland.nix inputs)
      ./sddm.nix
    ];
  };
}
