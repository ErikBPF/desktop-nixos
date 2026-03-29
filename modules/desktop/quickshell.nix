{
  config,
  inputs,
  ...
}: let
  cfgPath = config.configPath;
in {
  flake.modules.home.quickshell = {
    config,
    pkgs,
    ...
  }: let
    inherit (config.colorScheme) palette;
    qmlPath = cfgPath + "/quickshell/qml";
    scriptsPath = cfgPath + "/quickshell/scripts";
  in {
    home.packages = [inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default];

    home.file."Pictures/Wallpapers" = {
      source = cfgPath + "/themes/wallpapers";
      recursive = true;
    };

    xdg.configFile."quickshell/theme.json".text = builtins.toJSON {
      colors = {
        base00 = "#${palette.base00}";
        base01 = "#${palette.base01}";
        base02 = "#${palette.base02}";
        base03 = "#${palette.base03}";
        base04 = "#${palette.base04}";
        base05 = "#${palette.base05}";
        base06 = "#${palette.base06}";
        base07 = "#${palette.base07}";
        base08 = "#${palette.base08}";
        base09 = "#${palette.base09}";
        base0A = "#${palette.base0A}";
        base0B = "#${palette.base0B}";
        base0C = "#${palette.base0C}";
        base0D = "#${palette.base0D}";
        base0E = "#${palette.base0E}";
        base0F = "#${palette.base0F}";
      };
      fonts = {
        monospace = "JetBrainsMono Nerd Font";
        sans = "Noto Sans";
        serif = "Noto Serif";
      };
      bar = {
        height = 32;
        fontSize = 11;
        iconSize = 14;
        opacity = 0.85;
        borderRadius = 8;
      };
    };

    systemd.user.services.swww-daemon = {
      Unit = {
        Description = "swww wallpaper daemon";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
        Wants = ["swww-wallpaper.service"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.swww}/bin/swww-daemon";
        Restart = "on-failure";
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    systemd.user.services.swww-wallpaper = {
      Unit = {
        Description = "Set wallpaper via swww";
        After = ["swww-daemon.service"];
        Requires = ["swww-daemon.service"];
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 10); do ${pkgs.swww}/bin/swww query && exit 0; sleep 0.5; done; exit 1'";
        ExecStart = "${pkgs.swww}/bin/swww img /home/erik/Pictures/Wallpapers/wallpaper.png --transition-type fade";
      };
    };

    xdg.configFile."quickshell/qml/qmldir".text = ''
      singleton Style 1.0 Style.qml
    '';

    xdg.configFile."quickshell/qml/Style.qml".source = qmlPath + "/Style.qml";
    xdg.configFile."quickshell/qml/Shell.qml".source = qmlPath + "/Shell.qml";
    xdg.configFile."quickshell/qml/CalendarPopup.qml".source = qmlPath + "/CalendarPopup.qml";
    xdg.configFile."quickshell/qml/MusicPopup.qml".source = qmlPath + "/MusicPopup.qml";
    xdg.configFile."quickshell/qml/BatteryPopup.qml".source = qmlPath + "/BatteryPopup.qml";
    xdg.configFile."quickshell/qml/NetworkPopup.qml".source = qmlPath + "/NetworkPopup.qml";
    xdg.configFile."quickshell/qml/WallpaperPopup.qml".source = qmlPath + "/WallpaperPopup.qml";
    xdg.configFile."quickshell/qml/MonitorPopup.qml".source = qmlPath + "/MonitorPopup.qml";
    xdg.configFile."quickshell/qml/FocusTimePopup.qml".source = qmlPath + "/FocusTimePopup.qml";
    xdg.configFile."quickshell/qml/StewartPopup.qml".source = qmlPath + "/StewartPopup.qml";
    xdg.configFile."quickshell/qml/PowerPopup.qml".source = qmlPath + "/PowerPopup.qml";
    xdg.configFile."quickshell/scripts/poll_network.sh" = {
      source = scriptsPath + "/poll_network.sh";
      executable = true;
    };
    xdg.configFile."quickshell/scripts/sys_info.sh" = {
      source = scriptsPath + "/sys_info.sh";
      executable = true;
    };
    xdg.configFile."quickshell/scripts/poll_all.sh" = {
      source = scriptsPath + "/poll_all.sh";
      executable = true;
    };
    xdg.configFile."quickshell/scripts/poll_fast.sh" = {
      source = scriptsPath + "/poll_fast.sh";
      executable = true;
    };
    xdg.configFile."quickshell/scripts/poll_cpu.sh" = {
      source = scriptsPath + "/poll_cpu.sh";
      executable = true;
    };
    xdg.configFile."quickshell/scripts/qs_manager.sh" = {
      source = scriptsPath + "/qs_manager.sh";
      executable = true;
    };
  };
}
