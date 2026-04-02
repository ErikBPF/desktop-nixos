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
        # Don't relabel disk images — the qcow2 lives on an ext4 vault mount
        # that libvirt-qemu (uid 301) can read via group=kvm. Relabeling would
        # reset ownership to libvirt-qemu after each VM stop, breaking restarts.
        verbatimConfig = ''
          remember_owner = 0
        '';
      };
    };

    # Allow erik to manage VMs without sudo
    users.users.erik.extraGroups = ["libvirtd" "kvm"];

    # qemu-libvirtd (uid 301) needs kvm group to read the qcow2 disk image
    # at /home/erik/vault/vms/ which is owned erik:kvm.
    users.users.qemu-libvirtd.extraGroups = ["kvm"];

    # --- HAOS VM definition ---
    # QCOW2:  /home/erik/vault/vms/haos_ova-17.1.qcow2  (official KVM image, on vault HDD)
    # NVRAM:  /var/lib/libvirt/qemu/nvram/haos_VARS.fd   (EFI vars, persisted across rebuilds)
    # USB:    Silicon Labs CP210x (0x10c4:0xea60) — Zigbee/Z-Wave stick, passed through
    # MAC:    52:54:00:d6:a5:ce — DHCP reservation 192.168.10.115 on router
    # Bridge: br0 (eno1 enslaved) — HAOS appears directly on the LAN
    environment.etc."libvirt/qemu/haos.xml" = {
      source = ./haos-domain.xml;
      mode = "0600";
      user = "root";
      group = "root";
    };

    # /home/erik needs world-execute so libvirt-qemu (uid qemu-libvirtd) can
    # traverse the path to /home/erik/vault/vms/haos_ova-17.1.qcow2.
    # home-manager resets /home/erik to 0700 on every activation, so tmpfiles
    # alone cannot maintain this. The haos-vm service fixes it before each start.
    systemd.tmpfiles.rules = [
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
        DISK="/home/erik/vault/vms/haos_ova-17.1.qcow2"

        if [ ! -f "$DISK" ]; then
          echo "HAOS disk not found at $DISK — retrying in 30s"
          exit 1
        fi

        # Fix path traversal: home-manager resets /home/erik to 0700 on every
        # activation, blocking qemu-libvirtd from reaching the qcow2.
        chmod 711 /home/erik
        chmod 711 /home/erik/vault
        chmod 750 /home/erik/vault/vms
        # Ensure the qcow2 is group-readable by kvm (qemu-libvirtd is in kvm).
        chmod 660 "$DISK"
        chown erik:kvm "$DISK"

        # Define (or redefine) the domain from the NixOS-managed XML.
        # virsh define is idempotent — safe on every nixos-rebuild.
        $VIRSH define /etc/libvirt/qemu/haos.xml

        # Enable autostart so libvirt starts it on next libvirtd.service start.
        $VIRSH autostart haos

        # Remove any stale managed-save image. After a NixOS rebuild the QEMU
        # version may change, making the save file unrestorable (SIGPIPE in
        # libvirt_iohelper). A cold boot is always safe; HAOS journals to disk.
        if $VIRSH managedsave-dumpxml haos &>/dev/null; then
          echo "Removing stale managed-save image"
          $VIRSH managedsave-remove haos
        fi

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
