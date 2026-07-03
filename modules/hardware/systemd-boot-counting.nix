_: {
  # Shared UEFI bootloader: systemd-boot with automatic-boot-assessment (boot
  # counting). Replaces GRUB so a generation that fails to reach
  # boot-complete.target is demoted after N tries and the firmware boots the
  # last-good entry — GRUB has no equivalent, which is what blocked safe
  # unattended reboots on the GPU hosts. Verified in a VM
  # (nixosTests.systemd-boot.bootCounting) on the pinned nixpkgs before rollout.
  #
  # Hosts importing this still set their own ESP-dependent
  # boot.loader.systemd-boot.configurationLimit and boot.loader.efi.* bits.
  #
  # GOTCHA: switching a host FROM GRUB needs a one-time `--install-bootloader`
  # deploy (NIXOS_INSTALL_BOOTLOADER=1). deploy-rs / plain `switch` do NOT set
  # that flag, so the first migration fails with "Could not find any previously
  # installed systemd-boot" until it is run once with the flag.
  flake.modules.nixos.systemd-boot-counting = {lib, ...}: {
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.systemd-boot = {
      enable = true;
      bootCounting = {
        enable = true;
        tries = 3;
      };
    };

    # Boot-counting decrements its try counter only when a failed boot actually
    # reboots. panic=10 covers the clean case: reboot 10 s after a kernel panic.
    #
    # NOTE: two more-aggressive helpers were tried and REVERTED after they
    # reboot-looped pathfinder (2026-07-03):
    #   - systemd.watchdog.runtimeTime resets a healthy, already-blessed
    #     generation on a timer — boot-counting can't undo a blessed entry.
    #   - boot.panic_on_fail turns any transient initrd hiccup (a slow/flaky
    #     device on a new kernel) into a panic→reboot instead of waiting.
    # Both converted recoverable boots into loops. Keep only panic=10; the rarer
    # hang cases fall to console/boot-counting across generations, not a loop.
    boot.kernelParams = ["panic=10"];
  };
}
