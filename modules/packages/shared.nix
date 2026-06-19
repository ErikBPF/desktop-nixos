_: {
  flake.modules.nixos.packages-shared = {
    pkgs,
    lib,
    ...
  }: {
    # The x86-leaning workstation toolbox (cloud/devops/GUI-dev + x86-only
    # binaries like rar/postman/lens) is gated to x86_64 so the headless
    # aarch64 print host (archinaut) gets a lean, portable subset. No behaviour
    # change on existing x86_64 hosts.
    environment.systemPackages = with pkgs;
      [
        # --- Version Control & Editors ---
        git
        vim
        rsync
        sqlite

        # --- Command-line Productivity ---
        openssl
        xh
        fzf
        zoxide
        ripgrep
        fd
        direnv

        # --- Build Essentials ---
        gnumake
        just
        gdb
        gcc
        pkg-config

        # --- Core System Utilities ---
        alejandra
        coreutils
        coreutils-prefixed
        util-linux
        uutils-coreutils-noprefix
        file
        gawk
        lsof
        dua
        duf
        dust
        ncdu
        eza
        p7zip
        wget
        curl
        grpcurl
        gping
        unzip
        zip
        zstd
        clamav

        # --- Nix Tools ---
        nix-btm
        nix-du
        nix-melt
        nix-output-monitor
        nix-prefetch-github
        nix-search
        nix-top
        nix-tree
        nix-update
        nix-web
        nil
        nixd
        nixfmt
        statix

        # --- Hardware Information ---
        btrfs-progs
        btrfs-snap
        dmidecode
        dool
        inxi
        lshw
        read-edid
        smartmontools
        upower
        usbutils
        evtest
        lm_sensors

        # --- System Monitoring ---
        stress
        hyperfine
        nmon
        psmisc
        htop
        zfxtop
        kmon

        # --- Secrets & Network ---
        sops
        atuin
        cifs-utils
        samba
        fuse
        fuse3
        nfs-utils
        sshuttle

        # --- TUI Applications ---
        lazygit
        lazydocker
        powertop
        fastfetch

        # --- Shell & Prompt ---
        starship
        yazi
        imagemagick
        exiftool
        ffmpegthumbnailer
        fontpreview
        unar
        poppler

        # --- Editors & Dev Tools ---
        devenv
        gh
        ffmpeg
        onefetch
        cpufetch
        ramfetch
        starfetch
        octofetch
        speedtest-rs
      ]
      # Workstation/cloud toolbox + x86-only binaries — x86_64 hosts only.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
        rar

        # --- DevOps & Cloud ---
        terraform
        terraform-ls
        terragrunt
        tenv
        docker-compose
        kubectl
        kubelogin
        kubectx
        k9s
        lens
        kubernetes-helm
        helmfile
        azure-storage-azcopy
        minikube

        # --- Editors & Dev Tools (x86-only / heavy) ---
        ngrok
        postman
        dbeaver-bin
      ];
  };
}
