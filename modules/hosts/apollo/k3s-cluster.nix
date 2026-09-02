# Rebuildable k3s cluster on Apollo: three embedded-etcd control planes and two
# workers, all NixOS MicroVMs on a private bridge. Workloads belong in GitOps.
{
  inputs,
  config,
  ...
}: let
  fleetUser = config.username;
  lanIp = config.flake.fleet.hosts.apollo.ip;
in {
  flake.modules.nixos.apollo-k3s-cluster = {
    config,
    lib,
    pkgs,
    ...
  }: let
    mkK3sNode = import ../../services/_k3s-node.nix;
    subnet = "10.251.0";
    hostIp = "${subnet}.1";
    workerCount = 2;
    workerMem = 16384;
    workerVcpu = 8;
    tokenDir = "/var/lib/k3s-cluster";
    snapshotDir = "/var/lib/k3s-etcd-snapshots";

    cpNames = ["cp-1" "cp-2" "cp-3"];
    workerNames = map (i: "w-${toString i}") (lib.range 1 workerCount);
    allNames = cpNames ++ workerNames;
    cpServers = lib.concatMapStringsSep "\n" (i: "        server ${subnet}.${toString (10 + i)}:6443;") [1 2 3];
    sshKeys = config.users.users.${fleetUser}.openssh.authorizedKeys.keys;

    nodeSpec = name:
      if lib.hasPrefix "cp-" name
      then let
        i = lib.toInt (lib.removePrefix "cp-" name);
      in {
        role = "server";
        nodeIp = "${subnet}.${toString (10 + i)}";
        clusterInit = i == 1;
        serverAddr =
          if i == 1
          then null
          else "https://${hostIp}:6443";
        controlPlane = true;
        cid = 10 + i;
        mac = "02:00:00:00:fc:0${toString i}";
        vcpu = 2;
        mem = 4096;
        disk = 16384;
      }
      else let
        i = lib.toInt (lib.removePrefix "w-" name);
      in {
        role = "agent";
        nodeIp = "${subnet}.${toString (20 + i)}";
        clusterInit = false;
        serverAddr = "https://${hostIp}:6443";
        controlPlane = false;
        cid = 20 + i;
        mac = "02:00:00:00:fd:0${toString i}";
        vcpu = workerVcpu;
        mem = workerMem;
        disk = 32768;
      };

    mkGuest = name: let
      s = nodeSpec name;
    in {
      imports = [
        (mkK3sNode {
          inherit (s) role nodeIp clusterInit serverAddr controlPlane;
          tokenFile = "/tokens/token";
          tlsSan = [hostIp lanIp "apollo"];
          etcdSnapshotDir = lib.optionalString s.controlPlane "/etcd-snapshots";
        })
      ];

      microvm = {
        hypervisor = "cloud-hypervisor";
        inherit (s) vcpu mem;
        vsock.cid = s.cid;
        interfaces = [
          {
            type = "tap";
            id = "vm-k3s-${name}";
            inherit (s) mac;
          }
        ];
        shares =
          [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
            {
              tag = "k3s-token";
              source = tokenDir;
              mountPoint = "/tokens";
              proto = "virtiofs";
            }
          ]
          ++ lib.optional s.controlPlane {
            tag = "etcd-snap";
            source = "${snapshotDir}/${name}";
            mountPoint = "/etcd-snapshots";
            proto = "virtiofs";
          }
          ++ lib.optional (name == "cp-1") {
            tag = "host-textfile";
            source = "/var/lib/node-exporter-textfile";
            mountPoint = "/host-textfile";
            proto = "virtiofs";
          };
        volumes = [
          {
            image = "root.img";
            mountPoint = "/";
            size = s.disk;
          }
        ];
      };

      systemd.network = {
        enable = true;
        networks."10-cluster" = {
          matchConfig = {
            Type = "ether";
            Kind = "!*";
          };
          networkConfig = {
            Address = "${s.nodeIp}/24";
            Gateway = hostIp;
            DHCP = "no";
          };
        };
        networks."99-k3s-unmanaged" = {
          matchConfig.Name = ["cni0" "flannel*" "veth*" "cali*" "vxlan*" "kube-*"];
          linkConfig.Unmanaged = "yes";
        };
      };

      networking.firewall.enable = false;
      boot.kernel.sysctl."vm.max_map_count" = 262144;
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keys = sshKeys;

      systemd.services.apollo-k3s-readiness = lib.mkIf (name == "cp-1") {
        description = "Publish Apollo k3s readiness for the host textfile collector";
        after = ["k3s.service"];
        wants = ["k3s.service"];
        path = [pkgs.coreutils pkgs.gnugrep pkgs.k3s];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          tmp=$(mktemp /host-textfile/.apollo-k3s.prom.XXXXXX)
          trap 'rm -f "$tmp"' EXIT
          ready=$(k3s kubectl get nodes \
            -o 'jsonpath={range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
            | grep -c '^True$' || true)
          {
            printf 'apollo_k3s_ready_nodes %s\n' "$ready"
            printf 'apollo_k3s_probe_last_success_seconds %s\n' "$(date +%s)"
          } >"$tmp"
          chmod 0644 "$tmp"
          mv "$tmp" /host-textfile/apollo-k3s.prom
          trap - EXIT
        '';
      };

      systemd.timers.apollo-k3s-readiness = lib.mkIf (name == "cp-1") {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "1m";
          Unit = "apollo-k3s-readiness.service";
        };
      };

      system.stateVersion = "25.11";
    };
  in {
    imports = [inputs.microvm.nixosModules.host];

    networking = {
      useNetworkd = true;
      firewall = {
        trustedInterfaces = ["br-k3s"];
        allowedTCPPorts = [6443];
      };
      nat = {
        enable = true;
        internalInterfaces = ["br-k3s"];
        externalInterface = "enp6s0";
      };
    };

    systemd.network = {
      netdevs."20-br-k3s".netdevConfig = {
        Name = "br-k3s";
        Kind = "bridge";
      };
      networks."20-br-k3s" = {
        matchConfig.Name = "br-k3s";
        address = ["${hostIp}/24"];
        linkConfig.RequiredForOnline = "no";
      };
      networks."21-k3s-tap" = {
        matchConfig.Name = "vm-k3s-*";
        networkConfig.Bridge = "br-k3s";
        linkConfig.RequiredForOnline = "no";
      };
    };

    services.nginx = {
      enable = true;
      streamConfig = ''
        upstream k3s-apiserver {
        ${cpServers}
        }
        server { listen 6443; proxy_pass k3s-apiserver; proxy_timeout 600s; }
      '';
    };

    microvm = {
      stateDir = "/var/lib/microvms";
      autostart = allNames;
      vms = lib.genAttrs allNames (name: {config = mkGuest name;});
    };

    systemd.services =
      {
        k3s-cluster-state = {
          description = "Provision Apollo k3s token and snapshot directories";
          wantedBy = ["multi-user.target"];
          before = map (name: "microvm@${name}.service") allNames;
          path = [pkgs.coreutils];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0700 ${tokenDir}
            if [ ! -s ${tokenDir}/token ]; then
              umask 077
              head -c 32 /dev/urandom | base64 > ${tokenDir}/token
            fi
            install -d -m 0700 ${lib.concatMapStringsSep " " (name: "${snapshotDir}/${name}") cpNames}
          '';
        };
      }
      // lib.mapAttrs' (name: _:
        lib.nameValuePair "microvm@${name}" {
          overrideStrategy = "asDropin";
          after = ["microvm@cp-1.service"];
        }) (lib.genAttrs workerNames (_: null));
  };
}
