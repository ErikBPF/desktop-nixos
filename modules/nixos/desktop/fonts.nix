{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.desktop.enable {
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
    ];
  };
}
