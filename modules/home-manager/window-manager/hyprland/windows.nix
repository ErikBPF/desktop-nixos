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

      # # Just dash of transparency
      # "opacity 0.97 0.9, class:.*"
      # # Normal chrome Youtube tabs
      # "opacity 1 1, class:^(chromium|google-chrome|google-chrome-unstable)$, title:.*Youtube.*"
      # "opacity 1 0.97, class:^(chromium|google-chrome|google-chrome-unstable)$"
      # "opacity 0.97 0.9, initialClass:^(chrome-.*-Default)$ # web apps"
      # "opacity 1 1, initialClass:^(chrome-youtube.*-Default)$ # Youtube"
      # "opacity 1 1, class:^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
      # "opacity 1 1, class:^(com.libretro.RetroArch|steam)$"

      # Fix some dragging issues with XWayland
      "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

      # Float in the middle for clipse clipboard manager
      "float, class:(clipse)"
      # "float, title:^(clipse)$"
      "size 622 652, class:(clipse)"
      "stayfocused, class:(clipse)"

      # windowrulev2=workspace 1 silent,class:^(brave)$
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

    windowrulev2 = [
      "opacity 0.8 0.70 override,class:^(com.mitchellh.ghostty)$"
      "opacity 0.97 0.90,class:.*"
      "opacity 1 1,class:^(brave-browser|chromium|google-chrome|google-chrome-unstable)$"
      "workspace 10, class:^(whatsapp-electron)$"
      "workspace 11, title:^(btop ~)$"
      "workspace 12, class:^(spotify)$"
      "workspace 10, class:^(teams-for-linux)$"
      "workspace 10, class:^(discord)$"
      "workspace 10, class:^(whatsapp-electron)$"
      "workspace 11 silent,class:^(kitty btop)$"
      "workspace 11 silent,title:^(Lens)$"
      "workspace 10 silent,class:^(teams-for-linux)$"
      "workspace 10 silent,class:^(discord)$"
      "workspace 10 silent,class:^(whatsapp-electron)$"
      
      "float,class:^(teams-for-linux)$"
      "float,class:^(discord)$"
      "float,class:^(whatsapp-electron)$"

      "move 12 646,class:^(whatsapp-electron)$"
      "size 1056 643,class:^(whatsapp-electron)$"
      "move 12 47,class:^(teams-for-linux)$"
      "size 1056 585,class:^(teams-for-linux)$"
      "move 12 1304,class:^(discord)$"
      "size 1056 603,class:^(discord)$"
    ];

    layerrule = [
      # Proper background blur for wofi
      # "blur,wofi"
      # "blur,waybar"
    ];
  };
}
