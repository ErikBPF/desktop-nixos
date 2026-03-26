{...}: {
  flake.modules.nixos.packages-desktop = {
    pkgs,
    lib,
    ...
  }: {
    environment.systemPackages = with pkgs;
      [
        # --- Hyprland Desktop ---
        hyprland
        quickshell
        hyprshot
        hyprpicker
        hyprpaper
        hyprsunset
        swww
        brightnessctl
        pamixer
        playerctl
        networkmanagerapplet
        gnome-themes-extra
        pavucontrol
        easyeffects
        wlr-randr
        libinput-gestures
        nwg-displays
        dconf
        ffmpegthumbnailer
        gnome-keyring
        gnome.gvfs
        imv

        # --- Desktop Utilities ---
        kitty
        ghostty
        libnotify
        nautilus
        blueman
        clipse
        cliphist
        grim
        slurp
        swappy
        rofi
        foot
        wiremix
        fcitx5
        fcitx5-gtk
        kdePackages.fcitx5-qt

        # --- Graphics & Hardware ---
        libGL
        libGLU
        libva
        libva-utils
        mesa
        hwinfo
        mesa-demos
        libinput
        gpu-viewer

        # --- Desktop Theming ---
        glib
        gsettings-desktop-schemas
        wlroots
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-utils
        desktop-file-utils
        kdePackages.polkit-kde-agent-1
        qt6.qtbase
        qt6.qtwayland
        tokyonight-gtk-theme
        papirus-icon-theme
        bibata-cursors
        vimix-cursors
        vimix-icon-theme
        vimix-gtk-themes
        seahorse
        libsecret

        # --- GUI Applications ---
        chromium
        vlc
        discord
        whatsapp-electron
        teams-for-linux
        brave
        noisetorch
        usbimager
        gparted
        mongodb-compass
        github-desktop
        code-cursor-fhs
        kiro-fhs
        kiro-cli
        cursor-cli
        antigravity-fhs
        opencode
        gemini-cli
        claude-code
        tailscale-systray
      ]
      ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
        spotify
      ];
  };
}
