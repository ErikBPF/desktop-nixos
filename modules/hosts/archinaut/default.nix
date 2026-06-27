{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.archinaut.module = {
    modulesPath,
    lib,
    ...
  }: {
    imports = [
      # Kernel-direct boot: the base SD-image builder (NOT sd-image-aarch64.nix,
      # which hardcodes u-boot + extlinux) plus archinaut-kernel-direct, which
      # supplies a GPU-firmware-direct bootloader (no u-boot). This is what lets
      # the Pi boot with the printer powered — the Klipper MCU on the GPIO UART
      # used to hang u-boot's serial console. See
      # docs/implemented/2026-06-20-archinaut-kernel-direct-boot.md.
      (modulesPath + "/installer/sd-card/sd-image.nix")
      m.nixos.archinaut-kernel-direct
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.archinaut-hardware
      m.nixos.klipper-host
      m.nixos.first-boot
      # NOTE: btrfs-snapshots intentionally omitted — the SD root is ext4.
      # NOTE: alloy (monitoring) intentionally omitted — ~260 MB RSS + CPU is
      # too heavy for the 1 GB Pi; it starved sshd during boot activation.
    ];

    # Rollback guard: the print stack must come back after an unattended upgrade.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
      "klipper.service"
      "moonraker.service"
    ];

    system.stateVersion = "25.11";

    # Unattended upgrades — built on orion (aarch64 via binfmt), substituted here.
    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#archinaut";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };

    # 1 GB RPi3 trims: no SMART-capable disk (SD card), and the RPi kernel
    # rejects the auditd netlink rule-load — disable both to keep boot clean.
    services.smartd.enable = lib.mkForce false;
    security.auditd.enable = lib.mkForce false;
    security.audit.enable = lib.mkForce false;

    # WiFi-only: blacklist the onboard USB ethernet (lan78xx). The C270 webcam
    # shares the Pi3's single dwc2 USB-2.0 bus with the NIC, and even an
    # idle/link-down lan78xx starved the camera's isochronous bandwidth —
    # continuous capture collapsed to 0fps within ~40s. With the NIC off the bus
    # (host is on WiFi now) the stream holds a steady ~24fps. Re-enable only if
    # reverting to wired. See modules/services/klipper-host.nix webcam block.
    boot.blacklistedKernelModules = ["lan78xx"];

    services.openssh.enable = true;
  };
}
