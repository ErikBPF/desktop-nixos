{lib, ...}: {
  flake.modules.nixos.orion-containers = {pkgs, ...}: {
    # Override Docker options set by profile-base → containers module.
    # NixOS asserts: dockerCompat → !docker.enable, so all three must be forced off.
    virtualisation.docker = {
      enable = lib.mkForce false;
      enableOnBoot = lib.mkForce false;
      autoPrune.enable = lib.mkForce false;
    };

    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      # dockerSocket.enable is intentionally omitted (R006 constraint)
      autoPrune.enable = true;
    };
    # homelab-net network is created by docker compose (not a systemd unit) — compose handles it.
  };
}
