{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.kepler.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.systemd-boot-counting
      m.nixos.kepler-hardware
      m.nixos.kepler-networking
      m.nixos.kepler-syncthing
      m.nixos.kepler-nas
      m.nixos.containers
      m.nixos.kepler-containers
      m.nixos.kepler-compose
      m.nixos.kepler-recovery-tooling
      m.nixos.kepler-k1-inventory-tooling
      m.nixos.kepler-k3s-cluster
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.alloy-containers
      m.nixos.power-desktop
      m.nixos.restic-offsite-target
      m.nixos.fleet-dns
    ];

    # Per-container metrics via the cAdvisor exporter in the host Alloy. Rootless
    # Podman socket (matches kepler-compose's dockerSocket). Feeds the fleet
    # container-down / crash-loop alerts on discovery.
    homelab.alloy.containerSocket = "unix:///run/user/1000/podman/podman.sock";

    # Off-site target for discovery's tofu-state restic backup (dedicated,
    # sftp-only user; repo on the bulk pool). Pairs with discovery's
    # services.resticTofuState.offsiteRepository.
    services.resticOffsiteTarget = {
      enable = true;
      dir = "/bulk/backups/restic-offsite";
      authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGl9rC3PIKoyAQVUJ2jNRfGwJrxmEea6c2oNhXK4AfkS restic-offsite-discovery-to-kepler";
    };

    services.fleetDns = {
      enable = true;
      interface = "enp5s0";
      queryLog = false;
      upstream = ["192.168.10.210" "1.1.1.1" "9.9.9.9"];
      sequentialUpstream = true;
    };

    # k3s test cluster (microvm nodes). Stage 1: single cp-1 VM (plumbing proof).
    # ⚠ Brings up systemd-networkd — deploy supervised (see the module header).
    kepler.k3s.enable = true;

    home-manager.users.${config.username}.imports = [
      m.home.kepler-ssh
    ];

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = true;

    # Bootloader: systemd-boot + boot-counting via the systemd-boot-counting
    # module imported above (grub off, panic=10). Migrated GRUB → systemd-boot
    # 2026-07-03; /boot is already the vfat ESP. ESP is 512 MB / initrds ~180 MB,
    # so cap at ~2 generations (same as GRUB held).
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.configurationLimit = 2;

    # ZFS hostId — generated from /etc/machine-id on live ISO (head -c 8 /etc/machine-id)
    networking.hostId = "cf7e11b5";

    # NB: transparent_hugepage=always was previously set here for "ARC + CUDA"
    # locality, but OpenZFS upstream guidance is explicit that THP=always
    # competes with ARC for contiguous memory and triggers khugepaged
    # compaction stalls under sustained IO. Leave THP at the kernel default
    # (madvise) on this host; the CUDA inference workload that motivated the
    # change is still future, and the ZFS pool is the primary daily driver.

    hardware.nvidia-container-toolkit.enable = true;

    # Allow the laptop's dedicated root-owned builder key. Client-side
    # scheduling caps this host at two ordinary x86_64 jobs and excludes
    # Kepler itself from using Kepler as a remote builder.
    users.users.${config.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop"
    ];

    system.autoUpgrade = {
      enable = true;
      flake = "git+https://github.com/ErikBPF/desktop-nixos?ref=main#kepler";
      # boot + in-window reboot: a live switch of an nvidia/kernel bump breaks the
      # running CUDA driver (module vs kernel mismatch) — the same reason the manual
      # path uses deploy-rs-boot. A fresh boot keeps them matched. randomizedDelaySec
      # staggers the 05:00 herd off the orion cache (which settles by 04:30).
      operation = "boot";
      flags = ["--show-trace"];
      allowReboot = true;
      dates = "05:00";
      randomizedDelaySec = "900";
      rebootWindow = {
        lower = "05:00";
        upper = "06:00";
      };
    };
  };
}
