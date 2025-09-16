{pkgs, lib, exclude_packages ? []}:
let
  # Essential Hyprland packages - cannot be excluded
  hyprlandPackages = with pkgs; [
    hyprland
    hyprshot
    hyprpicker
    hyprsunset
    brightnessctl
    pamixer
    playerctl
    networkmanagerapplet
    gnome-themes-extra
    pavucontrol
    easyeffects
    wlr-randr # Xrandr clone for wlroots compositors
    libinput
    libinput-gestures
  ];

  # Essential system packages - cannot be excluded
  systemPackages = with pkgs; [
    git
    vim
    kitty
    ghostty
    libnotify
    nautilus
    xh # A better curl
    alejandra
    blueberry
    clipse
    fzf
    zoxide
    ripgrep
    eza
    fd
    curl
    direnv
    unzip
    wget
    gnumake
    gdb # GNU Project Debugger
    glib
    gsettings-desktop-schemas
    libGL
    libGLU
    libva # Video acceleration API
    mesa # Open source 3D graphics library
    hwinfo # Hardware detection tool from openSUSE
    stress # Perform stress tests on CPU
    bottom # Better htop alternative
    btop # Better htop alternative
    glxinfo # Info for OpenGL & Mesa
    hyperfine # Command-line benchmarking tool
    nmon # System monitoring tool
    psmisc # killall, pstree, etc.
    lm_sensors # Tools for reading hardware sensors

    # --- Hardware Information Tools ---
    dmidecode # System hardware details
    dool # System statistics tool (dstat replacement)
    inxi # My swiss army knife
    lshw # List hardware
    lshw # List hardware
    pciutils # lspci
    read-edid # EDID information
    smartmontools # S.M.A.R.T. monitoring
    upower # D-Bus service for power management
    usbutils # lsusb
    evtest # Live-test keyboards
    libinput # Handle inputs in Wayland
        # --- Build Essentials ---
    gnumake # Make files
    gnutls # GNU transport layer security library
    gcc # GNU compiler collection
    pkg-config # Package information finder

    # --- Core System Utilities ---
    coreutils # Basic GNU tools
    coreutils-prefixed # Prefixed version of coreutils
    util-linux # Includes lscpu
    uutils-coreutils-noprefix # An improvement over coreutils
    dua # Interactive disk usage analyzer
    dust # Modern du replacement with colors
    eza # Modern ls replacement
    file # Determine file types
    gawk # GNU's awk
    lsof # Tool to list open files
    ncdu # NCurses disk usage analyzer
    p7zip # 7-Zip archiver
    rar # RAR archives
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
    nixfmt-rfc-style # Official formatter
  ];

  # Discretionary packages - can be excluded by user
  discretionaryPackages = with pkgs; [
    sops
    swappy
    wf-recorder
    grim
    slurp
    nfs-utils
    gparted


    # TUIs
    lazygit
    lazydocker
    btop
    powertop
    fastfetch

    # GUIs
    chromium
    vlc

    # Coding
    python3Full
    uv
    go
    go-protobuf
    protoc-gen-go
    protoc-gen-go-grpc
    zulu23
    jre21_minimal
    zulu17
    zulu11

    spark

    terraform
    terragrunt
    tenv
    # Development tools
    github-desktop
    gh

    code-cursor
    opencode
    gemini-cli
    ngrok
    postman
    # Containers
    docker-compose
    ffmpeg
    kubectl
    kubelogin
    kubectx
    k9s
    lens
    kubernetes-helm
    helmfile
    dbeaver-bin
    azure-cli
    azure-storage-azcopy
    discord

        foot
    kitty
    
    # Terminal utilities
    starship  # customizable prompt
    
    # Wayland terminal tools
    ydotool   # input automation for Wayland
    wtype     # text input for Wayland
    wl-clipboard  # clipboard utilities for Wayland
  ] ++ lib.optionals (pkgs.system == "x86_64-linux") [
    spotify
  ];

  # Only allow excluding discretionary packages to prevent breaking the system
  filteredDiscretionaryPackages = lib.lists.subtractLists exclude_packages discretionaryPackages;
  allSystemPackages = hyprlandPackages ++ systemPackages ++ nixPackages ++ filteredDiscretionaryPackages;
in {
  # Regular packages
  systemPackages = allSystemPackages;

  homePackages = with pkgs; [
    bat
    neofetch
    fastfetch
    nordpass
    ente-auth


    btop
    iotop  # io monitoring
    iftop  # network monitoring
    
    # System monitoring and debugging
    strace  # system call monitoring
    ltrace  # library call monitoring
    lsof    # list open files
    sysstat
    lm_sensors  # for `sensors` command
    ethtool
    pciutils  # lspci
    usbutils  # lsusb

        # Archive utilities
    zip
    xz
    unzip
    p7zip
    
    # Command line utilities
    ripgrep  # recursively searches directories for a regex pattern
    ripgrep-all # Ripgrep for extended file types
    jq       # A lightweight and flexible command-line JSON processor
    yq-go    # yaml processer
    eza      # A modern replacement for 'ls'
    fzf      # A command-line fuzzy finder
    
    # Networking tools
    mtr      # A network diagnostic tool
    iperf3
    dnsutils # `dig` + `nslookup`
    dig # DNS lookup utility
    ipfetch # Neofetch for IP addresses
    ldns     # replacement of `dig`, provides `drill`
    aria2    # multi-protocol download utility
    socat    # replacement of openbsd-netcat
    nmap     # network discovery and security auditing
    ipcalc   # IPv4/v6 address calculator
    
    # Misc utilities
    cowsay
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg

    #printers
    cups
    hplip
  ];
}
