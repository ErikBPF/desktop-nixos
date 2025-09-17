{
  config,
  pkgs,
  lib,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs lib;};
in {
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Initial login experience
  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd Hyprland";
  };
  systemd.tmpfiles.rules = [
    "d '/var/cache/tuigreet' - greeter greeter - -"
  ];

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  hardware.graphics = {
    enable = true;
  };

  # xdg.portal = {
  #   enable = true;
  #   extraPortals = with pkgs; [
  #     xdg-desktop-portal-hyprland
  #   ];
  # };

  # Install packages
  environment.systemPackages = packages.systemPackages;
  programs.direnv.enable = true;

  services.xserver = {
    # ...
    # displayManager = {
		# 	sddm.enable = true;
    #         sddm.theme = "${import ./sddm-theme.nix { inherit pkgs; }}";
		# };

    xkb = {
      layout = "qwerty-fr";
      variant = "qwerty-fr";
      extraLayouts = {
        qwerty-fr = {
          description = "QWERTY with French symbols and diacritics";
          languages = ["eng"];
          symbolsFile = builtins.fetchurl {
            url = "https://raw.githubusercontent.com/ErikBPF/desktop-nixos/refs/heads/main/config/keyboard/us_qwerty-fr";
          };
        };
      };
    };
  };

  security.sudo = {
    enable = true;
    extraRules = [
      {
        groups = ["wheel"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  # Networking
  services.resolved.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  networking = {
    networkmanager.enable = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    nerd-fonts.caskaydia-mono
  ];
}
