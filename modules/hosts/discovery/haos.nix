{lib, ...}: {
  flake.modules.nixos.discovery-haos = {
    pkgs,
    config,
    ...
  }: {
    # --- KVM / libvirt ---
    virtualisation.libvirtd = {
      enable = true;
      # Cleanly shut the VM down on host shutdown instead of suspending (saving
      # RAM state). A saved state is invalid after a kernel/generation change, so
      # libvirt-guests fails to resume it on the next boot; HAOS then starts fresh
      # anyway (onBoot defaults to "start"). Shutting down avoids the failed unit.
      onShutdown = "shutdown";
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

    # qemu-libvirtd (uid 301) needs kvm group to read the qcow2 disk image.
    users.users.qemu-libvirtd.extraGroups = ["kvm"];

    # Present the existing vault-backed VM directory outside the user home.
    # QEMU reaches /srv/vms directly, so /home/erik can remain private (0700).
    fileSystems."/srv/vms" = {
      device = "/home/erik/vault/vms";
      fsType = "none";
      options = ["bind" "x-systemd.requires-mounts-for=/home/erik/vault"];
    };

    # --- HAOS VM definition ---
    # QCOW2:  /srv/vms/haos_ova-17.1.qcow2  (bind-mounted from the vault HDD)
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

    # Declarative VM lifecycle: define + autostart on every boot.
    # - Idempotent: virsh define is a no-op if XML is unchanged.
    # - virsh autostart enables libvirt's own start-on-boot mechanism.
    # - Retries every 30s until the disk image is present (handles first-boot
    #   case where the qcow2 may still be copying to the vault).
    systemd.services.haos-vm = {
      description = "Define and autostart Home Assistant OS VM";
      wantedBy = ["multi-user.target"];
      after = ["libvirtd.service" "srv-vms.mount"];
      requires = ["libvirtd.service" "srv-vms.mount"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 0; # unlimited retries
      };

      script = ''
        VIRSH="${pkgs.libvirt}/bin/virsh"
        DISK="/srv/vms/haos_ova-17.1.qcow2"

        if [ ! -f "$DISK" ]; then
          echo "HAOS disk not found at $DISK — retrying in 30s"
          exit 1
        fi

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

        # Repair: libvirt autostart can race USB enumeration on boot —
        # startupPolicy=optional then boots the VM with the Zigbee stick
        # marked missing='yes' and zigbee2mqtt dies inside HAOS. If the
        # running domain has exactly one 10c4 entry and it is the missing
        # one, hot-attach the stick once it shows up on the host.
        XML=$($VIRSH dumpxml haos)
        if echo "$XML" | grep -q "missing='yes'" \
          && [ "$(echo "$XML" | grep -c "vendor id='0x10c4'")" -eq 1 ]; then
          for _ in $(seq 1 12); do
            if ${pkgs.usbutils}/bin/lsusb -d 10c4:ea60 >/dev/null 2>&1; then
              echo "<hostdev mode='subsystem' type='usb' managed='yes'><source><vendor id='0x10c4'/><product id='0xea60'/></source></hostdev>" > /run/haos-zigbee-attach.xml
              $VIRSH attach-device haos /run/haos-zigbee-attach.xml --live
              break
            fi
            echo "Zigbee stick not enumerated yet — waiting 5s"
            sleep 5
          done
        fi
      '';
    };

    environment.systemPackages = with pkgs; [
      virt-manager
    ];
  };
}
