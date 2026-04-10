{config, ...}: let
  inherit (config) username;
in {
  flake.modules.nixos.distributed-builds = {
    config,
    lib,
    ...
  }: {
    # Opt-in per host. Requires:
    #   1. /root/.ssh/nix-builder private key present on this host
    #   2. Corresponding public key in orion's authorizedKeys (see hosts/orion/default.nix)
    options.nix.distributedBuildsOrion.enable =
      lib.mkEnableOption "offload nix builds to orion via ssh-ng";

    config = lib.mkIf config.nix.distributedBuildsOrion.enable {
      nix.distributedBuilds = true;
      nix.buildMachines = [
        {
          hostName = "192.168.10.220";
          sshUser = username;
          sshKey = "/root/.ssh/nix-builder";
          systems = ["x86_64-linux"];
          protocol = "ssh-ng";
          maxJobs = 16;
          speedFactor = 4;
          supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
        }
      ];

      # nix-daemon SSHes to orion on port 2222 (hardened SSH — see networking/openssh.nix).
      # This replaces the imperative /root/.ssh/config entry used during bootstrap.
      programs.ssh.extraConfig = ''
        Host 192.168.10.220
          Port 2222
      '';
    };
  };
}
