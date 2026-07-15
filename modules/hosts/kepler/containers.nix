_: {
  flake.modules.nixos.kepler-containers = {
    pkgs,
    config,
    ...
  }: {
    # Kepler runs rootless Podman with docker-compat (m.nixos.containers,
    # imported explicitly in default.nix — no longer part of profile-base).
    # No runtime override here — orchestration.nix targets the rootless socket
    # at /run/user/1000/podman/podman.sock by default.

    # Pre-create the rootless podman storage dirs so the first `podman info`
    # after a fresh boot doesn't race the storage driver init. (Already
    # populated on this host — included for idempotency on reprovision.)
    environment.systemPackages = with pkgs; [
      docker-compose
      podman-compose
    ];

    _module.args.keplerContainers = {inherit (config) username;};
  };
}
