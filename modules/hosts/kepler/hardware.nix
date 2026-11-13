{inputs, ...}: {
  flake.modules.nixos.kepler-hardware = {
    config,
    lib,
    pkgs,
    modulesPath,
    ...
  }: let
    kernelPkgs = import inputs.nixpkgs-gpu-kernel {
      inherit (pkgs.stdenv.hostPlatform) system;
      config = config.nixpkgs.config;
    };
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # --- Hardware detection (AMD Ryzen 5 3600, Radeon Tobago PRO (1002:665f)) ---
    boot.kernelPackages = lib.mkForce kernelPkgs.linuxPackages_7_2;
    boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usb_storage" "sd_mod" "usbhid"];
    boot.initrd.kernelModules = ["amdgpu"];
    boot.kernelModules = [
      "kvm-amd"
      "mpt3sas" # LSI SAS3008 HBA (IT mode confirmed) — no drives yet, ready for HDDs
      "amdgpu"
    ];

    networking.useDHCP = lib.mkDefault false; # set per-interface in networking.nix
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # --- ZFS kernel support ---
    boot.supportedFilesystems = ["zfs"];
    boot.zfs.forceImportRoot = false;
    # fast-pool: 4x Kingston 480GB SATA SSDs (sda/sdb/sdd/sde) via RAIDZ1 (~1.4TB usable)
    # bulk-pool: add here once HDDs are installed and connected to the SAS HBA
    boot.zfs.extraPools = ["fast-pool"];

    # --- Disko: OS on Toshiba 256GB M.2 SATA (by-id, confirmed sdc on live ISO) ---
    # No PCIe NVMe — M.2 slot is SATA-only on this board.
    # ZFS pools are NOT declared in disko — created imperatively (see docs/reference/kepler-zfs-setup.md).
    disko.devices = {
      disk.os = {
        type = "disk";
        device = "/dev/disk/by-id/ata-TOSHIBA_KSG60ZMV256G_M.2_2280_256GB_58SF70G0F5WP";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["defaults"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-L" "nixos" "-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                  };
                  "/log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["subvol=log" "compress=zstd" "noatime"];
                  };
                };
              };
            };
          };
        };
      };
    };
    fileSystems."/var/log".neededForBoot = true;

    # --- ZFS pool mounts ---
    # nofail: boot proceeds even if the pool isn't imported yet (not created, or HBA empty).
    # X-mount.mkdir: creates the mountpoint directory automatically.
    fileSystems."/fast" = {
      device = "fast-pool/data";
      fsType = "zfs";
      options = ["zfsutil" "X-mount.mkdir" "nofail"];
    };
    fileSystems."/bulk" = {
      device = "bulk-pool/data";
      fsType = "zfs";
      options = ["zfsutil" "X-mount.mkdir" "nofail"];
    };
    # These datasets are mounted above; `zfs mount -a` races their generated
    # mount units and leaves zfs-mount.service failed despite healthy mounts.
    systemd.services.zfs-mount.enable = false;

    # Apollo's observed amdgpu-bound Radeon; no CUDA workload on Kepler.
    services.xserver.videoDrivers = ["amdgpu"];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    environment.systemPackages = with pkgs; [
      e2fsprogs
      zfs
    ];

    # Monthly scrub for all imported ZFS pools
    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };

    # Sanoid snapshot timeline for the data pool. Scrub protects against
    # bitrot; snapshots protect against deletes/bad writes. Local-only —
    # off-host backup is the restic chain in servarr (kepler/sync.yml).
    services.sanoid = {
      enable = true;
      templates.production = {
        hourly = 24;
        daily = 14;
        monthly = 3;
        autosnap = true;
        autoprune = true;
      };
      datasets."fast-pool/data" = {
        useTemplate = ["production"];
        recursive = true;
      };
      # Add "bulk-pool/data" here once the HDDs land on the SAS HBA.
    };
  };
}
