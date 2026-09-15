_: {
  flake.modules.nixos.endeavour-always-on = {lib, ...}: {
    # Endeavour is a desk-docked workstation. Never suspend/hibernate the OS,
    # and keep USB peripherals (incl. the USB ethernet dongle) plus the built-in
    # enp2s0 NIC powered at all times, on AC and battery alike.
    services.logind.settings.Login = {
      IdleAction = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };
    systemd.sleep.settings.Sleep = {
      AllowSuspend = false;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    # Sleep is refused, so UPower's default HybridSleep can no longer run on a
    # critical battery. Shut down cleanly instead of cutting power at 0%.
    services.upower.criticalPowerAction = "PowerOff";

    # USB: no autosuspend at all, so externally attached devices never drop.
    boot.kernelParams = ["usbcore.autosuspend=-1"];

    services.tlp.settings = {
      USB_AUTOSUSPEND = 0;
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "on";
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";
      # power.nix sets powersupersave on battery; keep the NIC link stable.
      PCIE_ASPM_ON_BAT = lib.mkForce "default";
    };
  };
}
