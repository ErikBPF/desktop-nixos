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
    # Rootless Podman records the API client's OOM score on the containers it
    # creates, and a non-zero value makes crun reject detached execs with
    # "write to /proc/self/oom_score_adj: permission denied". User units cannot
    # lower themselves below the floor their manager inherited, so the floor
    # has to move first: user@.service is spawned by PID 1 with CAP_SYS_RESOURCE.
    systemd.services."user@".serviceConfig.OOMScoreAdjust = 0;

    environment.systemPackages = with pkgs; [
      podman-compose
    ];
  };
}
