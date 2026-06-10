_: {
  flake.modules.nixos.kepler-containers = {
    pkgs,
    config,
    ...
  }: {
    # Kepler runs rootless Podman with docker-compat (m.nixos.containers,
    # imported explicitly in default.nix — no longer part of profile-base).
    # No runtime override here — orchestration.nix targets the rootless socket
    # at /run/user/1000/podman/podman.sock by default. The NVIDIA runtime is
    # exposed via CDI (Container Device Interface) by
    # `hardware.nvidia-container-toolkit.enable = true` in default.nix:
    # podman + docker-compose translate `runtime: nvidia` into CDI device
    # injection (`--device nvidia.com/gpu=all`) automatically.

    # Pre-create the rootless podman storage dirs so the first `podman info`
    # after a fresh boot doesn't race the storage driver init. (Already
    # populated on this host — included for idempotency on reprovision.)
    environment.systemPackages = with pkgs; [
      docker-compose
      podman-compose
    ];

    # Disable user-namespace remapping for the rootless container that the
    # ai-serving stack uses — F5-TTS needs uid 0 inside the container to
    # write the HF cache under /models/hf without crashing on `EACCES`.
    # (No change required currently — rootless podman default works because
    # the bind-mounted /fast paths are owned by erik:users, and HF cache
    # writes go inside the user namespace.)
    _module.args.keplerContainers = {inherit (config) username;};
  };
}
