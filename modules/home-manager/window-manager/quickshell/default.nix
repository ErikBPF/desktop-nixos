{
  config,
  inputs,
  pkgs,
  ...
}: let
  palette = config.colorScheme.palette;
in {
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

  # Wallpaper files (previously managed by hyprpaper.nix)
  home.file."Pictures/Wallpapers" = {
    source = ../../../../config/themes/wallpapers;
    recursive = true;
  };

  # swww daemon as systemd user service
  systemd.user.services.swww-daemon = {
    Unit = {
      Description = "swww wallpaper daemon";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.swww}/bin/swww-daemon";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # Set wallpaper after swww-daemon starts
  systemd.user.services.swww-wallpaper = {
    Unit = {
      Description = "Set wallpaper via swww";
      After = ["swww-daemon.service"];
      Requires = ["swww-daemon.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.swww}/bin/swww img /home/erik/Pictures/Wallpapers/wallpaper.png --transition-type fade";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  xdg.configFile."quickshell/qml/qmldir".text = ''
    singleton Style 1.0 Style.qml
  '';

  xdg.configFile."quickshell/qml/Style.qml".source = ./qml/Style.qml;
  xdg.configFile."quickshell/qml/Shell.qml".source = ./qml/Shell.qml;
  xdg.configFile."quickshell/qml/CalendarPopup.qml".source = ./qml/CalendarPopup.qml;
  xdg.configFile."quickshell/qml/MusicPopup.qml".source = ./qml/MusicPopup.qml;
  xdg.configFile."quickshell/qml/BatteryPopup.qml".source = ./qml/BatteryPopup.qml;
  xdg.configFile."quickshell/qml/NetworkPopup.qml".source = ./qml/NetworkPopup.qml;
  xdg.configFile."quickshell/qml/WallpaperPopup.qml".source = ./qml/WallpaperPopup.qml;
  xdg.configFile."quickshell/qml/MonitorPopup.qml".source = ./qml/MonitorPopup.qml;
  xdg.configFile."quickshell/qml/FocusTimePopup.qml".source = ./qml/FocusTimePopup.qml;
  xdg.configFile."quickshell/qml/StewartPopup.qml".source = ./qml/StewartPopup.qml;
  xdg.configFile."quickshell/qml/PowerPopup.qml".source = ./qml/PowerPopup.qml;
  xdg.configFile."quickshell/scripts/poll_network.sh" = {
    source = ./scripts/poll_network.sh;
    executable = true;
  };
  xdg.configFile."quickshell/scripts/sys_info.sh" = {
    source = ./scripts/sys_info.sh;
    executable = true;
  };
  xdg.configFile."quickshell/scripts/poll_all.sh" = {
    source = ./scripts/poll_all.sh;
    executable = true;
  };
  xdg.configFile."quickshell/scripts/poll_fast.sh" = {
    source = ./scripts/poll_fast.sh;
    executable = true;
  };
  xdg.configFile."quickshell/scripts/poll_cpu.sh" = {
    source = ./scripts/poll_cpu.sh;
    executable = true;
  };
  xdg.configFile."quickshell/scripts/qs_manager.sh" = {
    source = ./scripts/qs_manager.sh;
    executable = true;
  };
}
