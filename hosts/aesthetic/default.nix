{
  pkgs,
  config,
  ...
}: {
  imports = [./hardware-configuration.nix];


  networking.hostName = "aesthetic";

  services = {
    # for SSD/NVME
    fstrim.enable = true;
  };
}
