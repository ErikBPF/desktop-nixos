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
    # disko processes disks alphabetically (ssd1 before ssd2).
    # The btrfs RAID1 mkfs on ssd2/sda references ssd1/sdc's partition as the peer.
    # So ssd1 MUST be sdc (mirror) to get partitioned first; ssd2 is sda (primary).
    # sdb = Seagate ST4000DM004 3.6TB HDD — data disk, NOT managed by disko.
    disko.devices = {
      disk = {
        ssd1 = {
          # sdc: mirror SSD — partitioned first so /dev/sdc1 exists when sda's btrfs runs
          type = "disk";
          device = "/dev/sdc";
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
          # sda: primary SSD — ESP + btrfs RAID1 root (references sdc1 as RAID peer)
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                label = "boot";
                name = "ESP";
                size = "512M";
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
                  extraArgs = ["-L" "nixos" "-f" "-d" "raid1" "-m" "raid1" "/dev/sdc1"];
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
        # sdb (3.6TB HDD) is intentionally absent from disko.
        # It holds all docker volumes, media, and the HAOS QCOW2.
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
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    boot.kernelModules = [
      "kvm-intel"
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
    boot.initrd.kernelModules = ["nvidia"];
    boot.extraModulePackages = [config.boot.kernelPackages.nvidia_x11];
    boot.blacklistedKernelModules = ["nouveau"];

    environment.systemPackages = with pkgs; [
      nvtopPackages.nvidia
    ];
  };
}
