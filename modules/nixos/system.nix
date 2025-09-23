{
  config,
  pkgs,
  lib,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs lib;};
in {
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      # Enable experimental features (battery, LC3, etc.)
      settings = {
        General = {
          Experimental = true;
          Enable = "Source,Sink,Media,Socket";
        };
      };
    };
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    i2c.enable = true;
    steam-hardware.enable = true;
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

  systemd.tmpfiles.rules = [
      "d '/var/cache/tuigreet' - greeter greeter - -"
    ];

  # Services
  services = {
    xserver = {
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
    greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd Hyprland";
    };
    fstrim.enable = true;
    resolved.enable = true;
    udisks2.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
    # Bluetooth manager (tray + UI)
    blueman.enable = true;
    # Network service discovery for "Browse Network" in Thunar and SMB service discovery
    avahi = {
      enable = true;
      nssmdns4 = true;
    };
    # Optional: allow mounting WebDAV as a filesystem (in addition to GVFS WebDAV)
    davfs2.enable = true;
    # Secret Service provider for GVFS credentials (SFTP/SMB/WebDAV)
    gnome.gnome-keyring.enable = true;
    # Display manager for Hyprland
    # displayManager.gdm = {
    #   enable = true;
    #   wayland = true;
    # };
    printing.enable = true;
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
    };
    openssh.enable = true;
    tailscale.enable = true;
    atuin = {
      enable = true;
      # Optional: Configure a server for sync (uncomment and configure if needed)
      # server = {
      #   enable = true;
      #   host = "0.0.0.0";
      #   port = 8888;
      # };
    };
  };

  # Auto Tune
  services.bpftune.enable = true;
  programs.bcc.enable = true;

  security = {
    sudo = {
      enable = true;
    #   extraRules = [
    #     {
    #       groups = ["wheel"];
    #       commands = [
    #         {
    #           command = "ALL";
    #           options = ["NOPASSWD"];
    #         }
    #       ];
    #     }
    #   ];
    # };
    };
    rtkit.enable = true;
    polkit.enable = true;
    sudo.wheelNeedsPassword = false;
    pam.services = {
      greetd.enableGnomeKeyring = true;
      login.kwallet.enable = true;
      gdm.kwallet.enable = true;
      gdm-password.kwallet.enable = true;
      # hyprlock = { };
      # Unlock GNOME Keyring on login for GVFS credentials
      login.enableGnomeKeyring = true;
      gdm-password.enableGnomeKeyring = true;
    };
  };


  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    nerd-fonts.jetbrains-mono
  ];
}
