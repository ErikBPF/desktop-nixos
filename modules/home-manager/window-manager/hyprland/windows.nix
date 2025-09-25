{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
      "suppressevent maximize, class:.*"

      # Force chromium into a tile to deal with --app bug
      "tile, class:^(chromium)$"

      # Settings management
      "float, class:^(org.pulseaudio.pavucontrol|blueberry.py)$"

      # Float Steam, fullscreen RetroArch
      "float, class:^(steam)$"
      "fullscreen, class:^(com.libretro.RetroArch)$"

      # Just dash of transparency
      "opacity 0.97 0.9, class:.*"
      # Normal chrome Youtube tabs
      "opacity 1 1, class:^(chromium|google-chrome|google-chrome-unstable)$, title:.*Youtube.*"
      "opacity 1 0.97, class:^(chromium|google-chrome|google-chrome-unstable)$"
      "opacity 0.97 0.9, initialClass:^(chrome-.*-Default)$ # web apps"
      "opacity 1 1, initialClass:^(chrome-youtube.*-Default)$ # Youtube"
      "opacity 1 1, class:^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
      "opacity 1 1, class:^(com.libretro.RetroArch|steam)$"

      # Fix some dragging issues with XWayland
      "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

      # Float in the middle for clipse clipboard manager
      "float, class:(clipse)"
      # "float, title:^(clipse)$"
      "size 622 652, class:(clipse)"
      "stayfocused, class:(clipse)"

      #       windowrulev2=workspace 1 silent,class:^(brave)$
      # windowrulev2=workspace 11 silent,class:^(kitty btop)$
      # windowrulev2=workspace 11 silent,title:^(Lens)$
      # windowrulev2=workspace 10 silent,class:^(chrome-teams.microsoft.com__-Default)$
      # windowrulev2=workspace 10 silent,class:^(chrome-discord.com__app-Default)$
      # windowrulev2=workspace 10 silent,class:^(chrome-web.whatsapp.com__-Default)$
      # windowrulev2=float,class:^(chrome-teams.microsoft.com__-Default)$
      # windowrulev2=float,class:^(chrome-discord.com__app-Default)$
      # windowrulev2=float,class:^(chrome-web.whatsapp.com__-Default)$

      # windowrulev2=move 12 646,class:^(chrome-web.whatsapp.com__-Default)$
      # windowrulev2=size 1056 643,class:^(chrome-web.whatsapp.com__-Default)$
      # windowrulev2=move 12 47,class:^(chrome-teams.microsoft.com__-Default)$
      # windowrulev2=size 1056 585,class:^(chrome-teams.microsoft.com__-Default)$
      # windowrulev2=move 12 1304,class:^(chrome-discord.com__app-Default)$
      # windowrulev2=size 1056 603,class:^(chrome-discord.com__app-Default)$
    ];

    layerrule = [
      # Proper background blur for wofi
      # "blur,wofi"
      # "blur,waybar"
    ];
  };
}
