{...}: {
  services.xserver = {
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

  # services.displayManager = {
  #   # gdm = {
  #   #   enable = true;
  #   #   wayland = true;
  #   #   debug = true;
  #   # };
  # };

  # greetd = {
  #   enable = true;
  #   settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd Hyprland";
  # };

  # systemd.tmpfiles.rules = [
  #   "d '/var/cache/tuigreet' - greeter greeter - -"
  # ];

  # systemd.services.greetd.serviceConfig = {
  #   Type = "idle";
  #   StandardInput = "tty";
  #   StandardOutput = "tty";
  #   StandardError = "journal";
  #   TTYReset = true;
  #   TTYVHangup = true;
  #   TTYVTDisallocate = true;
  # };
}
