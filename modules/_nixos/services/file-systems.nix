{...}: {
  services = {
    udisks2.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
    # Optional: allow mounting WebDAV as a filesystem (in addition to GVFS WebDAV)
    davfs2.enable = true;
    # Secret Service provider for GVFS credentials (SFTP/SMB/WebDAV)
    gnome.gnome-keyring.enable = true;
  };
}
