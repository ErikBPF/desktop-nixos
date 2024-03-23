{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    hyprpaper
    hypridle
    hyprnome
    kitty
    swaylock-effects
    rofi-wayland
    dunst

    grim
    slurp
    wl-clipboard
    libnotify
    greetd.tuigreet
    brightnessctl
    alsa-utils
    pulsemixer
    cava
    libsecret
    piper

    keepassxc
    #nextcloud-client
    #obsidian
    logseq
    brave
    poweralertd
  ];

  services.ratbagd.enable = true;
  services.upower.enable = true;

  programs = {
    hyprland.enable = true;
  };

  xdg.mime.defaultApplications = {
    "text/html" = "brave-browser.desktop";
    "x-scheme-handler/http" = "brave-browser.desktop";
    "x-scheme-handler/https" = "brave-browser.desktop";
    "x-scheme-handler/about" = "brave-browser.desktop";
    "x-scheme-handler/unknown" = "brave-browser.desktop";
    "image/jpeg" = "brave-browser.desktop";
    "image/png" = "brave-browser.desktop";
    "image/svg+xml" = "brave-browser.desktop";
    "image/webp" = "brave-browser.desktop";
    "video/mp4" = "brave-browser.desktop";
    "video/mpeg" = "brave-browser.desktop";
    "video/webm" = "brave-browser.desktop";
    "application/pdf" = "brave-browser.desktop";
  };

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "VictorMono" ]; })
  ];

  security.pam.services.swaylock = {
    text = ''
      auth include login
    '';
  };
}
