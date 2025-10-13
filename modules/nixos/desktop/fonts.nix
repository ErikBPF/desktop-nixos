{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.desktop.enable {
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      nerd-fonts.jetbrains-mono
    ];
  };
}
