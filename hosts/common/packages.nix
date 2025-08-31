{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # Base system tools
    git
    vim
    brightnessctl
    ffmpeg
    alejandra
    qwerty-fr


    # Shell tools
    fzf
    zoxide
    ripgrep
    eza
    fd
    curl
    unzip
    wget
    gnumake

    # TUIs
    lazygit
    lazydocker
    btop
    powertop
    fastfetch

    # GUIs
    chromium
    brave


    spotify

   code-cursor

    # Containers
    docker-compose
    # podman-compose
  ];
}
