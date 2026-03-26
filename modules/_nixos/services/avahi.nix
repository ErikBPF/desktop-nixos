{...}: {
  # Network service discovery for "Browse Network" in Thunar and SMB service discovery
  services.avahi = {
    enable = false;
    # nssmdns4 = true;
    # publish.enable = false;
    # allowInterfaces = [ "lo" ];
  };
}
