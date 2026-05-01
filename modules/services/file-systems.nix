_: {
  flake.modules.nixos.file-systems = _: {
    services = {
      udisks2.enable = true;
      gvfs.enable = true;
      tumbler.enable = true;
      # Disabled: nixpkgs derivation broken (autoreconf m4 dir missing). Re-enable when upstream fixes.
      davfs2.enable = false;
      gnome.gnome-keyring.enable = true;
    };
  };
}
