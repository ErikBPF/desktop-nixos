_: {
  flake.modules.nixos.voyager-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/voyager";
      dockerSocket = "unix:///run/user/1000/podman/podman.sock";
      stacks = [
        "offsite"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /srv/backups/restic 0700 erik users - -"
    ];
  };
}
