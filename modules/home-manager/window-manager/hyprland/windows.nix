{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
      "suppress_event maximize, match:class .*"

      # Force chromium into a tile to deal with --app bug
      "tile on, match:class ^(chromium)$"

      # Settings management
      "float on, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"

      # Float Steam, fullscreen RetroArch
      "float on, match:class ^(steam)$"
      "fullscreen on, match:class ^(com.libretro.RetroArch)$"

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
      # "no_initial_focus on,match:class ^$,match:title ^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

      # Float in the middle for clipse clipboard manager
      "float on, match:class clipse"
      # "float, title:^(clipse)$"
      "size 622 652, match:class clipse"
      "stay_focused on, match:class clipse"

      "opacity 0.97 0.90, match:class .*"
      "opacity 0.90 0.80 override,match:class ^(com.mitchellh.ghostty)$"
      "opacity 1 1,match:class ^(brave-browser|chromium|google-chrome|google-chrome-unstable)$"
      "float on,match:class ^(teams-for-linux)$"
      "float on,match:class ^(discord)$"
      "float on,match:class ^(whatsapp-electron)$"

      "move 12 646,match:class ^(whatsapp-electron)$"
      "size 1056 643,match:class ^(whatsapp-electron)$"
      "move 12 47,match:class ^(teams-for-linux)$"
      "size 1056 585,match:class ^(teams-for-linux)$"
      "move 12 1304,match:class ^(discord)$"
      "size 1056 603,match:class ^(discord)$"

      "workspace 1, match:class ^(brave)$"
      "workspace 10, match:class ^(whatsapp-electron)$"
      "workspace 11, match:title ^(btop ~)$"
      "workspace 12, match:class ^(spotify)$"
      "workspace 10, match:class ^(teams-for-linux)$"
      "workspace 10, match:class ^(discord)$"
      "workspace 10, match:class ^(whatsapp-electron)$"
      "workspace 11 silent,match:title ^(btop ~)$"
      "workspace 11 silent,match:title ^(Lens)$"
      "workspace 10 silent,match:class ^(teams-for-linux)$"
      "workspace 10 silent,match:class ^(discord)$"
      "workspace 10 silent,match:class ^(whatsapp-electron)$"

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
      



    ];

    layerrule = [
      # Proper background blur for wofi
      # "blur,wofi"
      # "blur,waybar"
    ];
  };
}
