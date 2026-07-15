_: {
  flake.modules.nixos.discovery-hardware = {
    config,
    lib,
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # --- Hardware detection (Intel CPU, Quadro P2000) ---
    boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod"];

    networking.useDHCP = lib.mkDefault true;
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # --- Disko: 2x 480GB SSD RAID1 mirror (OS) ---
    # disko processes disks alphabetically (ssd1 before ssd2). Stable ATA IDs
    # prevent volatile sdX ordering from ever selecting the vault HDD.
    # The btrfs RAID1 mkfs on ssd2 references ssd1's partition as the peer.
    disko.devices = {
      disk = {
        ssd1 = {
          # Kingston serial ...098: mirror SSD, partitioned first.
          type = "disk";
          device = "/dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098";
          content = {
            type = "gpt";
            partitions = {
              mirror = {
                size = "100%";
                content = {
                  type = "btrfs";
                };
              };
            };
          };
        };
        ssd2 = {
          # Kingston serial ...105: primary SSD with ESP and RAID1 root.
          type = "disk";
          device = "/dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105";
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
                  extraArgs = [
                    "-L"
                    "nixos"
                    "-f"
                    "-d"
                    "raid1"
                    "-m"
                    "raid1"
                    "/dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098-part1"
                  ];
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
        # Seagate serial ZTT25R4M is intentionally absent from disko.
        # It holds vault data and the HAOS QCOW2; Docker currently lives on RAID.
        # Declared as a pre-existing mount below — nixos-anywhere will not touch it.
      };
    };

    # vault: 3.6TB HDD — pre-existing ext4, all homelab data lives here.
    # Using LABEL= so device order changes don't break the mount.
    # nofail: boot continues if the disk is briefly absent during reboot.
    fileSystems."/home/erik/vault" = {
      device = "/dev/disk/by-label/vault";
      fsType = "ext4";
      options = ["defaults" "noatime" "nofail"];
    };

    fileSystems."/var/log".neededForBoot = true;

    # --- Quadro P2000: headless NVENC, no display ---
    services.xserver.videoDrivers = ["nvidia"];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        libvdpau-va-gl
      ];
    };

    hardware.nvidia = {
      open = false;
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      nvidiaSettings = false;
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    };

    boot.kernelModules = [
      "kvm-intel"
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
    # nvidia is deliberately NOT in boot.initrd.kernelModules: discovery is
    # headless, so early KMS is pointless, and the nvidia module + GSP firmware
    # bloat the initrd to ~199 MB — which overflows the 512 MB ESP on deploy
    # (systemd-boot writes the new gen before pruning old). nvidia loads fine at
    # stage 2 from boot.kernelModules above; the GPU (transcode/compute/nvtop)
    # is unaffected. Do not re-add it here without shrinking the initrd first.
    boot.extraModulePackages = [config.boot.kernelPackages.nvidiaPackages.legacy_580];
    boot.blacklistedKernelModules = ["nouveau"];

    environment.systemPackages = with pkgs; [
      nvtopPackages.nvidia
    ];
  };
}
