{pkgs, ...}: {
  virtualisation = {
    spiceUSBRedirection.enable = true;

    libvirtd = {
      enable = true;

      qemu = {
        swtpm.enable = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    qemu
    spice
    spice-gtk
    spice-protocol
    virt-manager
    virt-viewer
    win-spice
    win-virtio
  ];
}
