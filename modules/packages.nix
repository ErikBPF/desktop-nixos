{
  pkgs,
  lib,
  exclude_packages ? [],
}: let
  # Essential Hyprland packages - cannot be excluded
  hyprlandPackages = with pkgs; [
    hyprland # The Hyprland Wayland compositor
    hyprshot # Screenshot tool for Hyprland
    hyprpicker # Color picker for Hyprland
    hyprpaper # Wallpaper manager for Hyprland
    hyprsunset # Day/night gamma adjustments for Hyprland
    brightnessctl # Control screen brightness
    pamixer # Pulseaudio command-line mixer
    playerctl # Control media players from the command-line
    networkmanagerapplet # System tray applet for NetworkManager
    gnome-themes-extra # Provides themes like Adwaita
    pavucontrol # PulseAudio Volume Control GUI
    easyeffects # Audio effects for PipeWire applications
    wlr-randr # Utility to manage outputs for wlroots compositors
    libinput-gestures # Adds gesture support from libinput
    nwg-displays # Display configuration tool for Wayland
    dconf # Low-level configuration system for GNOME
    ffmpegthumbnailer # Video thumbnailer using ffmpeg
    gnome-keyring # Password and secret manager for GNOME
    gnome.gvfs # Virtual file system for GNOME
    imv # Image viewer for Wayland
    noisetorch
  ];

  # Essential system packages - cannot be excluded
  systemPackages = with pkgs; [
    # --- Version Control & Editors ---
    git # Distributed version control system
    vim # Ubiquitous text editor
    rsync # Fast, versatile, remote (and local) file-copying tool
    sqlite # Self-contained, serverless, zero-configuration SQL database engine

    # --- Terminals ---
    kitty # Fast, feature-rich, GPU-based terminal emulator
    ghostty # GPU-accelerated terminal emulator with multiplexing

    # --- Core Desktop Utilities ---
    libnotify # Library for sending desktop notifications
    nautilus # Official file manager for the GNOME desktop
    blueberry # Bluetooth configuration tool for GNOME
    clipse # A clipboard manager for Wayland
    cliphist # Clipboard history manager for Wayland

    # --- Command-line Productivity ---
    xh # A friendly and fast tool for sending HTTP requests
    fzf # A command-line fuzzy finder
    zoxide # A smarter cd command that learns your habits
    ripgrep # A line-oriented search tool that recursively searches the current directory for a regex pattern
    fd # A simple, fast and user-friendly alternative to 'find'
    direnv # An environment switcher for the shell

    # --- Build Essentials & Development ---
    gnumake # A tool which controls the generation of executables
    just
    gdb # The GNU Project Debugger
    glib # Core application building blocks for libraries and applications written in C
    gsettings-desktop-schemas # Collection of GSettings schemas
    gcc # GNU compiler collection
    pkg-config # A helper tool used when compiling applications and libraries
    wlroots # Modular Wayland compositor library
    xdg-desktop-portal-hyprland # XDG desktop portal backend for Hyprland
    xdg-desktop-portal-gtk # XDG desktop portal backend for GTK
    xdg-utils # Command line utilities that assist applications with desktop integration
    desktop-file-utils # Command line utilities for working with desktop entries
    kdePackages.polkit-kde-agent-1
    qt6.qtbase
    qt6.qtwayland
    tokyonight-gtk-theme # Tokyo Night GTK theme
    papirus-icon-theme # Papirus icon theme
    bibata-cursors # Cursor theme with smooth animations
    vimix-cursors # Vimix cursor theme
    vimix-icon-theme # Vimix icon theme
    vimix-gtk-themes # Vimix GTK themes
    # kdePackages.kwallet
    # kdePackages.kwallet-pam
    # kdePackages.kate
    wiremix # Audio mixer for Wayland
    fcitx5 # Flexible Input Method Framework
    fcitx5-gtk # GTK input method module for fcitx5
    kdePackages.fcitx5-qt # Qt input method module for fcitx5
    devenv

    # --- Graphics & Hardware ---
    libGL # Mesa's implementation of the OpenGL API
    libGLU # Mesa's implementation of the GLU API
    libva # Video Acceleration (VA) API for Linux
    libva-utils # Video Acceleration (VA) utilities
    mesa # An open-source implementation of the OpenGL specification
    hwinfo # Hardware detection tool
    mesa-demos # A tool for diagnosing problems with OpenGL and GLX
    lm_sensors # Tools for reading hardware sensor data
    libinput # Library to handle input devices in Wayland compositors
    seahorse # GUI to manage the keyring
    libsecret # CLI tools (secret-tool)
    mongodb-compass # MongoDB GUI

    btrfs-progs # Btrfs filesystem utilities
    btrfs-snap # Btrfs snapshot management tool
    cifs-utils # Common Internet File System utilities
    samba # SMB/CIFS file, print, and login server for Unix
    fuse # Filesystem in Userspace
    fuse3 # Filesystem in Userspace (version 3)
    syncthing # Continuous file synchronization program
    syncthingtray # System tray application for Syncthing
    tailscale-systray # System tray application for Tailscale
    git-crypt # Transparent git encryption
    minikube # Local Kubernetes engine
    gpu-viewer # GPU information viewer
    speedtest-rs # Command line interface for testing internet bandwidth
    onefetch # Git repository summary on your terminal
    cpufetch # CPU architecture fetching tool
    ramfetch # RAM information fetching tool
    starfetch # Star Wars themed system information tool
    octofetch # GitHub user information fetching tool
    htop # Interactive process viewer
    zfxtop # ZFS monitoring tool
    kmon # Linux kernel manager and activity monitor

    # --- Hardware Information Tools ---
    dmidecode # Tool for dumping a computer's DMI (some say SMBIOS) table contents in a human-readable format
    dool # System statistics tool (dstat replacement)
    inxi # A full featured CLI system information tool
    lshw # A small tool to extract detailed information on the hardware configuration of the machine
    read-edid # Tools for reading monitor EDID information
    smartmontools # S.M.A.R.T. disk monitoring tools
    upower # D-Bus service for power management
    usbutils # Contains lsusb for inspecting USB devices
    evtest # Input device event monitor and query tool

    # --- System Monitoring & Stress Testing ---
    stress # A tool to impose a configurable amount of stress on your system
    hyperfine # A command-line benchmarking tool
    nmon # A single-screen performance monitoring tool for developers and sysadmins
    psmisc # A set of small utilities that use the proc filesystem (e.g., killall, pstree)

    # --- Core System Utilities ---
    alejandra # The uncompromising Nix code formatter
    coreutils # The GNU Core Utilities (ls, cp, mv, etc.)
    coreutils-prefixed # Prefixed version of coreutils (g-ls, g-cp)
    util-linux # A huge collection of essential Linux utilities (e.g., lscpu)
    uutils-coreutils-noprefix # A cross-platform rewrite of the GNU coreutils in Rust
    file # A utility for determining file types
    gawk # GNU's implementation of the AWK programming language
    lsof # A tool to list open files
    dua # Interactive disk usage analyzer
    dust # Modern du replacement with colors
    ncdu # NCurses disk usage analyzer
    eza # A modern replacement for 'ls'
    p7zip # 7-Zip archiver
    rar # RAR archives
    wget # A free software package for retrieving files using HTTP, HTTPS, FTP
    curl # Command line tool for transferring data with URLs
    unzip # Extract ZIP archives
    zip # Create ZIP archives
    zstd # Compression algorithm (optional Emacs dep)
  ];

  # Essential nix packages - cannot be excluded
  nixPackages = with pkgs; [
    nix-btm # Bottom-like system monitor for nix
    nix-du # Disk usage analyzer for nix store
    nix-melt # Ranger-like flake.lock viewer
    nix-output-monitor # Better nix build output
    nix-prefetch-github # Prefetch sources from github. Useful for computing commit hashes.
    nix-search # Search nix packages
    nix-top # Top-like process monitor for nix
    nix-tree # Explore nix store
    nix-update # Update nix package versions
    nix-web # Web interface for nix store
    nil # Nix language server (original)
    nixd # Nix language server (newer)
    nixfmt # Official formatter
  ];

  # Discretionary packages - can be excluded by user
  discretionaryPackages = with pkgs;
    [
      # Terminal utilities

      # Wayland terminal tools
      # --- Secrets Management ---
      sops # Editor of encrypted files
      atuin

      # --- Wayland Utilities ---
      grim # A screenshot utility for Wayland
      slurp # A command-line utility to select a region in a Wayland compositor

      # --- System & GUI Tools ---
      nfs-utils # Network File System utilities
      gparted # GNOME Partition Editor
      chromium # Open-source web browser
      vlc # A free and open source cross-platform multimedia player
      discord # Voice, video, and text chat app
      whatsapp-electron
      teams-for-linux
      foot # A fast, lightweight and minimalistic Wayland terminal emulator
      swappy # A Wayland screenshot tool

      # --- TUI Applications ---
      lazygit # A simple terminal UI for git commands
      lazydocker # A simple terminal UI for both docker and docker-compose
      powertop # A tool to diagnose issues with power consumption
      fastfetch # A neofetch-like tool for fetching system information and displaying it in a pretty way

      # --- Programming Languages & Runtimes ---
      python3Minimal # The Python programming language
      uv # An extremely fast Python package installer and resolver, written in Rust
      go # The Go programming language
      go-protobuf # Go bindings for protocol buffers
      protoc-gen-go # Go protocol buffer compiler plugin
      protoc-gen-go-grpc # Go gRPC compiler plugin

      # --- DevOps & Cloud ---
      terraform # Tool for building, changing, and versioning infrastructure safely and efficiently
      terraform-ls # Official language server for Terraform
      terragrunt # A thin wrapper for Terraform that provides extra tools
      tenv # A Terraform version manager
      docker-compose # A tool for defining and running multi-container Docker applications
      kubectl # Command line tool for controlling Kubernetes clusters
      kubelogin # A kubectl plugin for Kubernetes authentication using OIDC
      kubectx # A tool to switch between kubectl contexts
      k9s # A terminal based UI to interact with your Kubernetes clusters
      lens # The Kubernetes IDE
      kubernetes-helm # The Kubernetes package manager
      helmfile # A declarative spec for deploying Helm charts
      azure-cli # Command-line tools for Azure
      azure-storage-azcopy # A command-line utility for copying data to/from Microsoft Azure Blob and File storage

      brave # Privacy-focused web browser
      # --- Development Tools ---
      github-desktop # The official GitHub GUI client
      gh # Official GitHub CLI
      code-cursor-fhs # The Cursor editor, an AI-powered fork of VSCode
      opencode # The OpenCode-OSS CLI agent
      gemini-cli # A command-line interface for Google's Gemini models
      ngrok # Secure introspectable tunnels to localhost
      postman # A collaboration platform for API development
      dbeaver-bin # A universal database tool
      ffmpeg # A complete, cross-platform solution to record, convert and stream audio and video

      # --- Shell & Prompt ---
      starship # The minimal, blazing-fast, and infinitely customizable prompt for any shell
      yazi
      imagemagick
      exiftool
      ffmpegthumbnailer
      fontpreview
      unar
      poppler
      unar
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      spotify # A music streaming service
    ];

  # Only allow excluding discretionary packages to prevent breaking the system
  filteredDiscretionaryPackages = lib.lists.subtractLists exclude_packages discretionaryPackages;
  allSystemPackages = hyprlandPackages ++ systemPackages ++ nixPackages ++ filteredDiscretionaryPackages;
in {
  # Regular packages
  systemPackages = allSystemPackages;

  homePackages = with pkgs; [
    # --- Security & Authentication ---
    nordpass # Password manager by NordVPN
    ente-auth # A 2FA authenticator app with secure cloud backup
    gnupg # GNU Privacy Guard

    # --- System Monitoring & Debugging ---
    iotop # I/O monitoring tool
    iftop # Network traffic monitoring tool
    strace # System call monitoring
    ltrace # Library call monitoring
    sysstat # A collection of performance monitoring tools (e.g., iostat, mpstat)
    ethtool # A utility for controlling network drivers and hardware

    # --- Command-line Utilities ---
    bat # A cat(1) clone with wings
    neofetch # A command-line system information tool
    ripgrep-all # Ripgrep, but for more file types
    jq # A lightweight and flexible command-line JSON processor
    yq-go # A portable command-line YAML processor
    tree # A recursive directory listing program
    which # A utility to show the full path of commands
    cowsay # A program which generates ASCII pictures of a cow with a message

    # --- GNU Utilities ---
    gnused # GNU implementation of the sed stream editor
    gnutar # GNU tar

    # --- Networking Tools ---
    mtr # A network diagnostic tool that combines ping and traceroute
    iperf3 # A tool for active measurements of the maximum achievable bandwidth on IP networks
    dnsutils # Provides `dig` and `nslookup` for DNS queries
    ldns # A library to simplify DNS programming, provides `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # A relay for bidirectional data transfer between two independent data channels
    nmap # A free and open source utility for network discovery and security auditing
    ipcalc # An IPv4/v6 address calculator

    # --- Archive Utilities ---
    xz # XZ compression utilities

    # --- Printing ---
    cups # Common UNIX Printing System
    hplip # HP Linux Imaging and Printing
  ];
}
