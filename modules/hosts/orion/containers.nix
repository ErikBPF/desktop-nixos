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

    # Create the homelab-net Podman network on boot.
    # AI compose files declare this network as external — it must exist before containers start.
    systemd.services.podman-homelab-net = {
      description = "Create podman homelab-net network";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman network create homelab-net || true";
      };
    };
  };
}
