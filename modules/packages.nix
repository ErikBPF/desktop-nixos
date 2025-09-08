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
    gnome-themes-extra
    pavucontrol
    easyeffects
  ];

  # Essential system packages - cannot be excluded
  systemPackages = with pkgs; [
    git
    vim
    kitty
    ghostty
    libnotify
    nautilus
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
  ];

  # Discretionary packages - can be excluded by user
  discretionaryPackages = with pkgs; [

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
  allSystemPackages = hyprlandPackages ++ systemPackages ++ filteredDiscretionaryPackages;
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
    jq       # A lightweight and flexible command-line JSON processor
    yq-go    # yaml processer
    eza      # A modern replacement for 'ls'
    fzf      # A command-line fuzzy finder
    
    # Networking tools
    mtr      # A network diagnostic tool
    iperf3
    dnsutils # `dig` + `nslookup`
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
