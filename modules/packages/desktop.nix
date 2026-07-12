_: {
  flake.modules.nixos.packages-desktop = {pkgs, ...}: {
    # Auto-start Cloudflare WARP daemon (warp-svc.service ships with the package).
    systemd.packages = [pkgs.cloudflare-warp];
    systemd.services.warp-svc.wantedBy = ["multi-user.target"];

    environment.systemPackages = with pkgs; [
      # --- Hyprland Desktop ---
      hyprland
      quickshell
      hyprshot
      hyprpicker
      hyprsunset
      awww
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

      # --- CLI / QoL ---
      zellij # terminal multiplexer (splits, tabs, session persistence)
      tealdeer # tldr — command cheatsheets
      television # fast fuzzy picker (files/git/env)
      procs # modern ps
      bandwhich # live per-process network usage
      glow # render markdown in the terminal
      wl-screenrec # screen recording (Wayland, hw-encoded)
      satty # screenshot annotation

      # --- Desktop Utilities ---
      kitty
      ghostty
      libnotify
      nautilus
      nautilus-python # loads nautilus-open-any-terminal extension
      nautilus-open-any-terminal # right-click "Open in Terminal" → ghostty
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
      nvtopPackages.full # GPU monitoring for btop (Intel + AMD + NVIDIA)
      intel-gpu-tools # btop needs intel_gpu_top for Intel iGPUs without hwmon

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
      papirus-icon-theme
      bibata-cursors
      vimix-cursors
      vimix-icon-theme
      seahorse
      libsecret

      # --- GUI Applications ---
      moonlight-qt
      chromium
      vlc
      brave
      usbimager
      gparted
      orca-slicer
      # --- CAD / EDA (TPS43 touchpad mount + PCB work) ---
      kicad # EDA suite
      openscad # parametric .scad mounts
      # freecad — TEMPORARILY REMOVED 2026-07-12: build broken on the current
      # nixpkgs (gdal-minimal/pdal/vtk chain fails). Re-enable once upstream fixes.
      # freecad # gen_step.py STEP export (import FreeCAD, Part)
      # mongodb-compass — TEMPORARILY REMOVED 2026-07-12: build broken on the
      # current nixpkgs (wrapGAppsHook regression). Re-enable once upstream fixes.
      # mongodb-compass
      github-desktop
      opencode
      gemini-cli
      claude-code
      discord
      discordo
      obsidian
      spotify
      spotify-player
      teams-for-linux
      whatsapp-electron
      tailscale-systray
      cloudflare-warp
    ];
  };
}
