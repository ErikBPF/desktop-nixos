{
  config,
  pkgs,
  ...
}: {
  # Network service discovery for "Browse Network" in Thunar and SMB service discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
