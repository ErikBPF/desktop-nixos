{config, ...}: let
  inherit (config) username;
in {
  flake.modules.nixos.distributed-builds = {
    config,
    lib,
    ...
  }: {
    # Opt-in per host. Requires:
    #   1. Home Manager has materialized the SOPS-managed user SSH key
    #   2. Corresponding public key in each builder's authorizedKeys
    #      (see hosts/{orion,kepler}/default.nix)
    options.nix.distributedBuildsOrion.enable =
      lib.mkEnableOption "offload nix builds to orion via ssh-ng";
    options.nix.distributedBuildsKepler.enable =
      lib.mkEnableOption "offload ordinary nix builds to kepler via ssh-ng";

    config =
      lib.mkIf (
        config.nix.distributedBuildsOrion.enable
        || config.nix.distributedBuildsKepler.enable
      ) {
        nix.distributedBuilds = true;
        nix.buildMachines =
          lib.optional config.nix.distributedBuildsOrion.enable {
            hostName = "192.168.10.220";
            sshUser = username;
            sshKey = "/home/${username}/.ssh/id_ed25519";
            # aarch64 via orion's binfmt/qemu emulation (Pi hosts: archinaut).
            # Emulation is slower per-build than native, but registering it here
            # lets aarch64 jobs run at maxJobs parallelism instead of the serial
            # default-1 you get from an ad-hoc --builders override.
            systems = ["x86_64-linux" "aarch64-linux"];
            protocol = "ssh-ng";
            maxJobs = 16;
            speedFactor = 4;
            supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
          }
          ++ lib.optional (
            config.nix.distributedBuildsKepler.enable
            && config.networking.hostName != "kepler"
          ) {
            hostName = "192.168.10.230";
            sshUser = username;
            sshKey = "/home/${username}/.ssh/id_ed25519";
            systems = ["x86_64-linux"];
            protocol = "ssh-ng";
            # Keep capacity for ZFS, AI serving, and k3s microVMs. Kepler is a
            # spillover builder, not a target for VM tests or privileged builds.
            maxJobs = 2;
            speedFactor = 1;
            supportedFeatures = ["benchmark" "big-parallel"];
          };

        # nix-daemon SSHes to orion on port 2222 (hardened SSH — see networking/openssh.nix).
        # This replaces the imperative /root/.ssh/config entry used during bootstrap.
        programs.ssh.extraConfig = ''
          Host 192.168.10.220
            Port 2222
            StrictHostKeyChecking accept-new
          Host 192.168.10.230
            Port 2222
            StrictHostKeyChecking accept-new
        '';
      };
  };
}
