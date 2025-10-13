{pkgs, ...}: {
  virtualisation = {
    spiceUSBRedirection.enable = true;

    libvirtd = {
      enable = true;

      qemu = {
        swtpm.enable = true;
        ovmf.enable = true;
        ovmf.packages = [pkgs.OVMFFull.fd];
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
