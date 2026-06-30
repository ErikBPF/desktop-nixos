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
      m.nixos.kepler-hardware
      m.nixos.kepler-networking
      m.nixos.kepler-syncthing
      m.nixos.kepler-nas
      m.nixos.containers
      m.nixos.kepler-containers
      m.nixos.kepler-compose
      m.nixos.kepler-ai-serving
      m.nixos.kepler-k3s-cluster
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.alloy-containers
      m.nixos.power-desktop
      m.nixos.restic-offsite-target
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

    # k3s test cluster (microvm nodes). Stage 1: single cp-1 VM (plumbing proof).
    # ⚠ Brings up systemd-networkd — deploy supervised (see the module header).
    kepler.k3s.enable = true;

    home-manager.users.${config.username}.imports = [
      m.home.kepler-ssh
    ];

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = true;

    boot.loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = false;
        # kepler's initrds are ~180 MB (ZFS + nvidia + modules) and the ESP is only
        # 512 MB, so it can hold ~2 generations. 5 overflowed /boot. Keep 2.
        # NOTE: the deeper fix is a smaller initrd or a larger ESP — see below.
        configurationLimit = 2;
      };
    };

    # ZFS hostId — generated from /etc/machine-id on live ISO (head -c 8 /etc/machine-id)
    networking.hostId = "cf7e11b5";

    # NB: transparent_hugepage=always was previously set here for "ARC + CUDA"
    # locality, but OpenZFS upstream guidance is explicit that THP=always
    # competes with ARC for contiguous memory and triggers khugepaged
    # compaction stalls under sustained IO. Leave THP at the kernel default
    # (madvise) on this host; the CUDA inference workload that motivated the
    # change is still future, and the ZFS pool is the primary daily driver.

    # CUDA container toolkit for AI inference workloads
    hardware.nvidia-container-toolkit.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#kepler";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };
  };
}
