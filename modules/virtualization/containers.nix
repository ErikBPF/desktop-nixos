_: {
  flake.modules.nixos.containers = {
    pkgs,
    lib,
    ...
  }: {
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
    # The rootless API daemon runs at the user manager's default score (200),
    # and containers created through the socket inherit it. crun then rejects
    # detached execs with "write to /proc/self/oom_score_adj: permission denied",
    # which is what broke every Ofelia backup job.
    # A user unit cannot write below the floor its manager inherited, so lower
    # the floor first: user@.service is spawned by PID 1 with CAP_SYS_RESOURCE.
    systemd.services."user@".serviceConfig.OOMScoreAdjust = 0;
    systemd.user.services.podman.serviceConfig.OOMScoreAdjust = 0;

    environment.systemPackages = with pkgs; [
      podman-compose
    ];
  };
}
