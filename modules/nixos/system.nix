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
    usb-modeswitch.enable = true;
    sensor.iio.enable = true;
    i2c.enable = true;
    steam-hardware.enable = true;
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    # Hyprland module provides its own portal; include only GTK here to avoid duplicate units
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config = {
      common = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      };
    };
  };

  # Make Qt apps follow GNOME/GTK settings for closer match to GTK theme
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };

  # Install packages
  environment.systemPackages = packages.systemPackages;
  programs = {
    direnv.enable = true;
  };

  # systemd.tmpfiles.rules = [
  #   "d '/var/cache/tuigreet' - greeter greeter - -"
  # ];

  # Services
  services = {
    xserver = {
      #       displayManager.setupCommands = ''
      #   workaround for using NVIDIA Optimus without Bumblebee
      #   xrandr --setprovideroutputsource modesetting NVIDIA-0
      #   xrandr --auto
      # '';
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
    # ...
    # desktopManager.gnome.enable = true;
    displayManager = {
      # gdm = {
      #   enable = true;
      #   wayland = true;
      #   debug = true;
      # };
    };

    # greetd = {
    #   enable = true;
    #   settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd Hyprland";
    # };
    hardware = {
      bolt.enable = true;
    };
    fstrim = {
      enable = true;
      interval = "weekly";
      # udev.extraRules = ''

      # HDD
      # ACTION == "add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
      #   ATTR{queue/scheduler}="bfq"

      # SSD
      # ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
      #   ATTR{queue/scheduler}="mq-deadline"

      # NVMe SSD
      # ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
      #   ATTR{queue/scheduler}="none"
      # '';
    };
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
    smartd = {
      enable = true;
      autodetect = true;
    };
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };

    # Firewall
    fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "1h";
      bantime-increment.enable = true;
    };
    earlyoom = {
      enable = true;
      freeMemThreshold = 5;
      freeSwapThreshold = 10;
    };

    # Logrotate
    logrotate = {
      enable = true;
      settings = {
        "/var/log/omnixy/*.log" = {
          frequency = "weekly";
          rotate = 4;
          compress = true;
          delaycompress = true;
          notifempty = true;
          create = "644 root root";
        };
      };
    };
    acpid.enable = true;
    tailscale = {
      enable = true;
      openFirewall = true;
    };
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
    };
    rtkit.enable = true;
    polkit.enable = true;
    apparmor = {
      enable = true;
      packages = with pkgs; [
        apparmor-utils
        apparmor-profiles
      ];
    };
    sudo.wheelNeedsPassword = false;
    pam.services = {
      # greetd.enableGnomeKeyring = true;
      # greetd.kwallet.enable = false;
      sddm.enableGnomeKeyring = true;
      sddm.kwallet.enable = false;
      sddm-greeter.enableGnomeKeyring = true;
      # gdm.enableGnomeKeyring = true;
      # gdm.kwallet.enable = false;
      # gdm-greeter.enableGnomeKeyring = true;
      # gdm-password.kwallet.enable = true;
      # gdm-password.enableGnomeKeyring = true;
      hyprlock = {};
      login.enableGnomeKeyring = true;
      login.kwallet.enable = true;
    };
  };
  # systemd.services.greetd.serviceConfig = {
  #   Type = "idle";
  #   StandardInput = "tty";
  #   StandardOutput = "tty";
  #   StandardError = "journal";
  #   TTYReset = true;
  #   TTYVHangup = true;
  #   TTYVTDisallocate = true;
  # };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    nerd-fonts.jetbrains-mono
  ];
}
