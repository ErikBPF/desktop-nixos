{pkgs, ...}: {
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
    # podman = {
    #   enable = true;

    #   dockerCompat = true;
    #   defaultNetwork.settings.dns_enabled = true;
    # };
  };

  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
