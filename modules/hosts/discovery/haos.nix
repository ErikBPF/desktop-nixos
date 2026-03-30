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
    # QCOW2:  /home/erik/vault/vms/haos_ova-16.3.qcow2  (on sdb, survives OS rebuilds)
    # NVRAM:  /var/lib/libvirt/qemu/nvram/haos_VARS.fd   (restored from haos-backup/ in M003/S03)
    # USB:    Silicon Labs CP210x (0x10c4:0xea60) — Zigbee/Z-Wave stick, passed through to HAOS
    # MAC:    52:54:00:80:4a:0e — preserved so HAOS keeps its DHCP lease / LAN identity
    # Bridge: br0 (eno1 enslaved) — HAOS appears directly on the LAN
    #
    # Restore procedure (M003/S03):
    #   mkdir -p /home/erik/vault/vms
    #   rsync haos_ova-16.3.qcow2 → /home/erik/vault/vms/
    #   rsync haos_VARS.fd → /var/lib/libvirt/qemu/nvram/
    #   chown libvirt-qemu:kvm /var/lib/libvirt/qemu/nvram/haos_VARS.fd
    #   virsh define /etc/libvirt/qemu/haos.xml
    #   virsh start haos
    environment.etc."libvirt/qemu/haos.xml" = {
      source = ./haos-domain.xml;
      mode = "0600";
      user = "root";
      group = "root";
    };

    # OVMF firmware package (required at the path libvirt expects)
    environment.systemPackages = with pkgs; [
      virt-manager # for manual VM inspection if needed
    ];
  };
}
