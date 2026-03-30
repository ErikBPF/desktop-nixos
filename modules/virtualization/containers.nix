_: {
  flake.modules.nixos.containers = {pkgs, ...}: {
    virtualisation.docker.enable = false;

    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      # dockerSocket.enable intentionally omitted (conflicts with dockerCompat)
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
