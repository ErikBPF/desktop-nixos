_: {
  flake.modules.nixos.containers = {pkgs, ...}: {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
    environment.systemPackages = with pkgs; [
      podman-compose
    ];
  };
}
