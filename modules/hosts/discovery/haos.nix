{lib, ...}: {
  flake.modules.nixos.discovery-haos = {
    pkgs,
    config,
    ...
  }: {
    # --- KVM / libvirt ---
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # ovmf.enable removed in NixOS 25.05 — OVMF bundled with QEMU by default
        swtpm.enable = true; # TPM 2.0 emulator (HAOS requires it)
        runAsRoot = false;
      };
    };

    # Allow erik to manage VMs without sudo
    users.users.erik.extraGroups = ["libvirtd" "kvm"];

    # --- HAOS VM definition ---
    # QCOW2:  /home/erik/vault/vms/haos_ova-16.3.qcow2  (on vault HDD, survives OS rebuilds)
    # NVRAM:  /var/lib/libvirt/qemu/nvram/haos_VARS.fd   (EFI vars, persisted across rebuilds)
    # USB:    Silicon Labs CP210x (0x10c4:0xea60) — Zigbee/Z-Wave stick, passed through
    # MAC:    52:54:00:80:4a:0e — fixed so HAOS keeps its DHCP lease / LAN identity
    # Bridge: br0 (eno1 enslaved) — HAOS appears directly on the LAN
    environment.etc."libvirt/qemu/haos.xml" = {
      source = ./haos-domain.xml;
      mode = "0600";
      user = "root";
      group = "root";
    };

    # /home/erik needs world-execute so libvirt-qemu (uid qemu-libvirtd) can
    # traverse the path to /home/erik/vault/vms/haos_ova-16.3.qcow2.
    # home-manager sets drwx------ by default; override to drwx-----x.
    systemd.tmpfiles.rules = [
      "Z /home/erik 0711 erik users - -"
      "Z /home/erik/vault/vms - erik kvm - -"
    ];

    # Declarative VM lifecycle: define + autostart on every boot.
    # - Idempotent: virsh define is a no-op if XML is unchanged.
    # - virsh autostart enables libvirt's own start-on-boot mechanism.
    # - Retries every 30s until the disk image is present (handles first-boot
    #   case where the qcow2 may still be copying to the vault).
    systemd.services.haos-vm = {
      description = "Define and autostart Home Assistant OS VM";
      wantedBy = ["multi-user.target"];
      after = ["libvirtd.service" "home-erik-vault.mount"];
      requires = ["libvirtd.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 0; # unlimited retries
      };

      script = ''
        VIRSH="${pkgs.libvirt}/bin/virsh"
        DISK="/home/erik/vault/vms/haos_ova-16.3.qcow2"

        if [ ! -f "$DISK" ]; then
          echo "HAOS disk not found at $DISK — retrying in 30s"
          exit 1
        fi

        # Define (or redefine) the domain from the NixOS-managed XML.
        # virsh define is idempotent — safe on every nixos-rebuild.
        $VIRSH define /etc/libvirt/qemu/haos.xml

        # Enable autostart so libvirt starts it on next libvirtd.service start.
        $VIRSH autostart haos

        # Start now if not already running.
        if ! $VIRSH domstate haos 2>/dev/null | grep -q "running"; then
          $VIRSH start haos
        fi
      '';
    };

    environment.systemPackages = with pkgs; [
      virt-manager
    ];
  };
}
