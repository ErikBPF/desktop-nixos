{
  config,
  self,
  ...
}: let
  flakeConfig = config;
  inherit (flakeConfig) username;
  inherit (flakeConfig.flake.fleet) hosts;
  serverKeys = {
    kepler = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINSN7mhPQHSpTqO3+P0aHQqKQppNM5g3P3/9iS+9vFa4 nix-builder@kepler";
    discovery = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0321n0iMNbD6lmtYo8UpNa/7Ebm1tgsHqYhldC0BY6 nix-builder@discovery";
  };
  hostKeys = {
    orion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAdaVn+4eIM6ogsg5KsMbhCXAX7fK5n1xoqMEl6endXh";
    apollo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKgV3yaYhtTk4F3qNyMnfDsFFcbnLuCnZaU9XaHfHQm2";
  };
in {
  flake.modules.nixos.distributed-builds = {
    config,
    lib,
    ...
  }: let
    host = config.networking.hostName;
    enabled = config.nix.distributedBuildsOrion.enable || config.nix.distributedBuildsApollo.enable;
    server = builtins.hasAttr host serverKeys;
    builder = builtins.hasAttr host hostKeys;
    secretName = "nix-builders/${host}/ssh-key";
    identity = {
      sshUser =
        if server
        then "nix-ssh"
        else username;
      sshKey =
        if server
        then config.sops.secrets.${secretName}.path
        else "/home/${username}/.ssh/id_ed25519";
      protocol = "ssh-ng";
    };
  in {
    # Explicit client enrollment; builders also expose the restricted server endpoint.
    options.nix.distributedBuildsOrion.enable =
      lib.mkEnableOption "offload nix builds to orion via ssh-ng";
    options.nix.distributedBuildsApollo.enable =
      lib.mkEnableOption "offload nix builds to apollo via ssh-ng";

    config = lib.mkMerge [
      (lib.mkIf enabled {
        nix.distributedBuilds = true;
        nix.buildMachines =
          lib.optional (config.nix.distributedBuildsOrion.enable && host != "orion")
          (identity
            // {
              hostName = "orion-builder";
              # aarch64 via Orion's binfmt/qemu; no observed /dev/kvm on Orion.
              systems = ["i686-linux" "x86_64-linux" "aarch64-linux"];
              maxJobs = 16;
              speedFactor = 4;
              supportedFeatures = ["nixos-test" "benchmark" "big-parallel"];
            })
          ++ lib.optional (
            config.nix.distributedBuildsApollo.enable && host != "apollo"
          ) (identity
            // {
              hostName = "apollo-builder";
              systems = ["i686-linux" "x86_64-linux"];
              maxJobs = 6;
              speedFactor = 1;
              supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
            });
      })

      (lib.mkIf (enabled && builtins.elem host ["endeavour" "kepler" "discovery"]) {
        # Native remote hooks run first for ordinary derivations; one local job
        # remains when remote capacity is unavailable. cores is guidance, not quota.
        nix.settings = {
          max-jobs = lib.mkForce 1;
          cores = lib.mkForce 1;
        };
      })

      (lib.mkIf (enabled && server) {
        sops.secrets.${secretName} = {
          sopsFile = self + "/secrets/sops/secrets.yaml";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      })

      (lib.mkIf builder {
        # Native forced nix-daemon --stdio endpoint, not an administrative shell.
        # Keep signature checks: trustless builds may reject unsigned local inputs.
        nix.sshServe = {
          enable = true;
          protocol = "ssh-ng";
          trusted = false;
          keys = builtins.attrValues serverKeys;
        };
      })

      (lib.mkIf (enabled || builder) {
        programs.ssh.knownHosts =
          lib.mapAttrs (name: publicKey: {
            hostNames = ["[${hosts.${name}.ip}]:2222"];
            inherit publicKey;
          })
          hostKeys;
        # OpenSSH takes the first value: select LAN on local network, tailnet
        # otherwise. This is interface selection, not a LAN-health failover probe.
        programs.ssh.extraConfig =
          lib.concatMapStringsSep "\n" (name: ''
            Match originalhost ${name}-builder localnetwork 192.168.10.0/24
              HostName ${hosts.${name}.ip}
            Host ${name}-builder
              HostName ${hosts.${name}.tailscaleIp}
              Port 2222
              HostKeyAlias [${hosts.${name}.ip}]:2222
              StrictHostKeyChecking yes
              BatchMode yes
              ConnectTimeout 8
          '') ["orion" "apollo"]
          + "\nHost *\n";
      })
    ];
  };
}
