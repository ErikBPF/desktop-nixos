{...}: {
  flake.modules.nixos.packages-shared = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
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
      dust
      ncdu
      eza
      p7zip
      rar
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
      ngrok
      postman
      dbeaver-bin
      ffmpeg
      onefetch
      cpufetch
      ramfetch
      starfetch
      octofetch
      speedtest-rs
    ];
  };
}
