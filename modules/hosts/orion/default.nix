{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.orion.module = {
    pkgs,
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      inputs.jovian.nixosModules.default
      m.nixos.profile-base
      m.nixos.orion-hardware
      m.nixos.orion-networking
      m.nixos.orion-syncthing
      # desktop-ish concerns orion needs without the full profile-desktop:
      # qwerty-fr layout, steam-hardware udev (jovian), rootless podman,
      # udisks2/gvfs for removable media on the HTPC
      m.nixos.xserver
      m.nixos.peripherals
      m.nixos.containers
      m.nixos.file-systems
      m.nixos.orion-containers
      m.nixos.first-boot
      m.nixos.orion-jovian
      m.nixos.orion-sunshine
      m.nixos.hyprland
      m.nixos.audio
      m.nixos.bluetooth
      m.nixos.xdg-portal
      m.nixos.fonts
      m.nixos.alloy
      m.nixos.alloy-containers
      m.nixos.nix-cache
      m.nixos.kepler-nfs
      m.nixos.orchestration
      m.nixos.orion-compose
      m.nixos.power-desktop
      m.nixos.lact
      m.nixos.orion-lact
      m.nixos.btrfs-snapshots
      m.nixos.sccache-cache
    ];

    # Host the fleet's shared sccache (dev-loop cargo) cache on the tailnet.
    services.sccacheCache.enable = true;

    # Per-container metrics via the cAdvisor exporter in the host Alloy. Rootless
    # Podman socket (orchestration default, matches orion-compose). Feeds the
    # fleet container-down / crash-loop alerts on discovery.
    homelab.alloy.containerSocket = "unix:///run/user/1000/podman/podman.sock";

    # Rollback guard: orion is the fleet binary cache + build offload target.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
      "nix-serve.service"
    ];

    home-manager.users.${config.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.orion-ssh
        m.home.hyprland
        m.home.fonts
      ];
      inherit (config) colorScheme;
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Build aarch64 (the `archinaut` RPi3 print host) under qemu so its closure
    # and SD image can be produced here and substituted to the Pi.
    boot.binfmt.emulatedSystems = ["aarch64-linux"];

    boot = {
      kernelParams = [
        "nohibernate"
        # RDNA4 + MoE hybrid offload tuning (see servarr/machines/orion/KERNEL-TUNING.md).
        # Defeat PCIe ASPM latency on host->GPU weight/activation transfers.
        # NOTE: the kernel boolean `pcie_aspm=` only takes `off`/`force`; the
        # policy is set via the module parameter `pcie_aspm.policy=`.
        "pcie_aspm.policy=performance"
        # Force 2MB pages for CPU-side MoE shard tensors; trims TLB pressure.
        "transparent_hugepage=always"
        # Unlock amdgpu power-management features (CoreCtrl/LACT controls).
        "amdgpu.ppfeaturemask=0xffffffff"
        # NOTE: `pci=realloc=on` was tried here and bricked boot — the kernel
        # tried to reassign BARs without firmware-reserved 64-bit MMIO above
        # 4 GiB and something downstream (NVMe/NIC enumeration) hung. ReBAR
        # is now deferred to a BIOS change (KERNEL-TUNING-DEFERRED.md D5)
        # — `Above 4G Decoding` + `Re-Size BAR Support` must be toggled in
        # BIOS first; software cannot work around the missing MMIO window.
      ];
      kernel.sysctl = {
        # 62GB RAM + zramSwap disabled below: keep anon pages resident, avoid
        # any swap activity racing with VRAM eviction during long-ctx inference.
        "vm.swappiness" = 1;
        # Steam games hit AC-locked atomics; default split-lock penalty
        # (warn+sleep) stutters game threads. Disable on a single-user HTPC.
        "kernel.split_lock_mitigate" = 0;
      };
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          useOSProber = false;
          timeoutStyle = "menu";
          configurationLimit = 3;
        };
        timeout = 3;
      };
    };

    services.btrfs.autoScrub.enable = true;

    # Allow laptop's nix-builder root key to trigger builds via ssh-ng
    users.users.${config.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop"
    ];

    # zramSwap intentionally disabled: 62GB host RAM is enough for the 21GB
    # GGUF + CPU-side MoE shards + containers. vm.swappiness=1 above assumes
    # no swap competes with VRAM eviction during long-context inference.
    zramSwap.enable = false;

    # earlyoom from m.nixos.maintenance sets freeSwapThreshold=10. earlyoom
    # 1.9 refuses any non-zero swap threshold when swap_total=0 ("value X
    # exceeds limit 0") and the NixOS option clamps to 1..100, so we cannot
    # zero it. Just disable earlyoom on Orion: 62GB RAM + no swap + kernel
    # OOM killer covers the residual risk, and freeMemThreshold=5 isn't
    # load-bearing on a single-purpose inference host.
    services.earlyoom.enable = lib.mkForce false;

    # bpftune (also from m.nixos.maintenance) auto-tunes vm.* sysctls under
    # observed memory pressure. It can silently raise vm.swappiness above 1
    # and reset vm.vfs_cache_pressure toward the kernel default, undoing the
    # static tuning above. Disable on Orion: the swap-avoidance + cache
    # retention invariants must not be re-tuned at runtime during inference.
    services.bpftune.enable = lib.mkForce false;

    # Pin all amdgpu IRQs to CPU0 so the 16-thread inference pool on cores
    # 1..15 keeps its L2/L3 hot. IRQ numbers change across reboots so resolve
    # them at service start, not at eval.
    # Pin amdgpu IRQs once amdgpu has registered with the kernel. amdgpu is
    # loaded from the initrd, so by multi-user.target the IRQ lines exist in
    # /proc/interrupts — no After= ordering needed. (A previous version
    # ordered after systemd-udev-settle.service, but that unit is not pulled
    # into the multi-user.target dependency graph on modern NixOS, making
    # the ordering hint a no-op.)
    systemd.services.amdgpu-irq-pin = {
      description = "Pin amdgpu IRQs to CPU0 for inference cache locality";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for irq in $(${pkgs.gnugrep}/bin/grep amdgpu /proc/interrupts | ${pkgs.gawk}/bin/awk -F: '{print $1}' | ${pkgs.coreutils}/bin/tr -d ' '); do
          echo 0 > /proc/irq/$irq/smp_affinity_list || true
        done
      '';
    };

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#orion";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };

    services.openssh.enable = true;
  };
}
