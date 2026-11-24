_: {
  flake.modules.nixos.containers = {pkgs, lib, ...}: {
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
    # The rootless API daemon must not carry a non-zero OOM score: containers
    # created through the socket inherit it, and crun then rejects detached
    # execs with "write to /proc/self/oom_score_adj: permission denied".
    systemd.user.services.podman.serviceConfig.OOMScoreAdjust = lib.mkForce 0;

    environment.systemPackages = with pkgs; [
      podman-compose
    ];
  };
}
