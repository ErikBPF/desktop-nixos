_: {
  flake.modules.nixos.file-systems = _: {
    services = {
      udisks2.enable = true;
      gvfs.enable = true;
      tumbler.enable = true;
      davfs2.enable = true;
      gnome.gnome-keyring.enable = true;
    };
  };
}
