{config, ...}: let
  inherit (config) fleet;
in {
  flake.modules.nixos.kepler-nfs = {config, ...}: let
    server =
      if config.networking.hostName == "apollo"
      then fleet.hosts.kepler.ip
      else "kepler";
  in {
    # NFS client mounts for Kepler's fast-pool and bulk-pool.
    # MagicDNS resolves "kepler" to its Tailscale IP; Apollo uses LAN because its
    # tagged Tailscale identity cannot see Kepler in its peer map.
    # nofail: boot continues if Kepler is offline or the mount times out.
    # x-systemd.automount: mount is not attempted until first access (lazy).
    # x-systemd.mount-timeout: fail fast if Kepler is unreachable.
    #
    # Mountpoints are under /mnt/nfs/ (not /home/erik/nfs/) so that bwrap sandboxes
    # (used by Nix, flatpak, etc.) can bind-mount /home without encountering these
    # automount points and failing with "Unable to apply mount flags: remount ... No such device".
    fileSystems."/mnt/nfs/fast" = {
      device = "${server}:/fast";
      fsType = "nfs";
      options = [
        "nfsvers=4"
        "nolock"
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

    fileSystems."/mnt/nfs/bulk" = {
      device = "${server}:/bulk";
      fsType = "nfs";
      options = [
        "nfsvers=4"
        "nolock"
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
      "d /mnt/nfs      0755 erik users -"
      "d /mnt/nfs/fast 0755 erik users -"
      "d /mnt/nfs/bulk 0755 erik users -"
    ];
  };
}
