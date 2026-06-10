_: {
  # Snapper timeline snapshots for /home on btrfs hosts. Scrubs (enabled
  # per-host via services.btrfs.autoScrub) protect against bitrot; these
  # protect against fat-fingered deletes and bad migrations. Local-only —
  # off-host backup is the syncthing→discovery + restic chain.
  flake.modules.nixos.btrfs-snapshots = _: {
    # tmpfiles 'v' creates /home/.snapshots as a btrfs subvolume if missing
    # (snapper expects it to exist; the NixOS module doesn't create it).
    systemd.tmpfiles.rules = ["v /home/.snapshots 0750 root root - -"];

    services.snapper.configs.home = {
      SUBVOLUME = "/home";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 24;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };
}
