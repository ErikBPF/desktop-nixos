_: {
  flake.modules.nixos.kepler-nfs = _: {
    # NFS client mounts for Kepler's fast-pool and bulk-pool.
    # Exported over Tailscale only — MagicDNS resolves "kepler" to its Tailscale IP.
    # nofail: boot continues if Kepler is offline or the mount times out.
    # x-systemd.automount: mount is not attempted until first access (lazy).
    # x-systemd.mount-timeout: fail fast if Kepler is unreachable.
    fileSystems."/home/erik/nfs/fast" = {
      device = "kepler:/fast";
      fsType = "nfs";
      options = [
        "nfsvers=4"
        "soft"
        "timeo=30"
        "retrans=2"
        "x-systemd.automount"
        "x-systemd.mount-timeout=10"
        "x-systemd.idle-timeout=600"
        "noauto"
        "nofail"
        "_netdev"
      ];
    };

    fileSystems."/home/erik/nfs/bulk" = {
      device = "kepler:/bulk";
      fsType = "nfs";
      options = [
        "nfsvers=4"
        "soft"
        "timeo=30"
        "retrans=2"
        "x-systemd.automount"
        "x-systemd.mount-timeout=10"
        "x-systemd.idle-timeout=600"
        "noauto"
        "nofail"
        "_netdev"
      ];
    };

    # Ensure mountpoint directories exist
    systemd.tmpfiles.rules = [
      "d /home/erik/nfs      0755 erik users -"
      "d /home/erik/nfs/fast 0755 erik users -"
      "d /home/erik/nfs/bulk 0755 erik users -"
    ];
  };
}
