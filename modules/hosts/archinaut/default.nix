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
      # RPi3 aarch64 SD image: extlinux + u-boot-rpi3 + RPi firmware + DTBs,
      # and the sdImage builder (config.system.build.sdImage).
      (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
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

    services.openssh.enable = true;
  };
}
