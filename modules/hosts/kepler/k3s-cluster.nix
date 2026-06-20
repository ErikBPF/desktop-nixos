# k3s test cluster on kepler — each node a NixOS MicroVM.
# See docs/proposals/2026-06-19-kepler-k3s-microvm-cluster.md.
#
# STAGE 2: full topology — 3 control-plane (HA embedded etcd, NoSchedule-tainted)
# + a scalable worker pool. Nodes join via cp-1 directly for now; the kepler L4 LB
# (.245 admin / .250 ingress) and platform baseline are the next steps.
#
# Plumbing proven in stage 1: cloud-hypervisor + virtiofs /nix + private br-k3s
# bridge + k3s offline from baked airgap images (cp-1 Ready on real hardware).
#
# Gated behind `kepler.k3s.enable`. ⚠ Uses systemd-networkd — deploy supervised.
{
  inputs,
  config,
  ...
}: let
  fleetUser = config.username; # flake-parts top-level option (meta.nix)
in {
  flake.modules.nixos.kepler-k3s-cluster = {
    config,
    lib,
    ...
  }: let
    cfg = config.kepler.k3s;
    mkK3sNode = import ../../services/_k3s-node.nix;

    subnet = "10.250.0";
    hostIp = "${subnet}.1"; # kepler on br-k3s = cluster gateway + LB registration

    # LAN-published endpoints, fronted by kepler's L4 LB (RFC §5.3).
    apiVip = "192.168.10.245"; # admin / kubectl
    ingressVip = "192.168.10.250"; # ingress (backend = ingress-nginx NodePort, 4c)
    ingressNodePort = 30443;

    # LB upstream server lists, generated from the topology.
    cpServers = lib.concatMapStringsSep "\n" (i: "        server ${subnet}.${toString (10 + i)}:6443;") [1 2 3];
    workerServers = lib.concatMapStringsSep "\n" (i: "        server ${subnet}.${toString (20 + i)}:${toString ingressNodePort};") (lib.range 1 cfg.workerCount);

    tokenDir = "/var/lib/k3s-cluster";

    # Reuse the fleet authorized key (user.nix) rather than a 3rd hardcoded copy —
    # guest root login trusts the same key.
    sshKeys = config.users.users.${fleetUser}.openssh.authorizedKeys.keys;

    # --- topology -----------------------------------------------------------
    # 3 control-plane nodes (fixed — etcd quorum). cp-1 bootstraps, cp-2/3 join.
    cpNames = ["cp-1" "cp-2" "cp-3"];
    workerNames = map (n: "w-${toString n}") (lib.range 1 cfg.workerCount);
    allNames = cpNames ++ workerNames;

    cpIndex = name: lib.toInt (lib.removePrefix "cp-" name); # 1..3
    workerIndex = name: lib.toInt (lib.removePrefix "w-" name); # 1..N

    # Per-node spec, derived from the name so scaling = bump workerCount.
    nodeSpec = name:
      if lib.hasPrefix "cp-" name
      then let
        i = cpIndex name;
      in {
        role = "server";
        # Tainted (NoSchedule), not headless: CPs run the agent (kube-proxy/flannel)
        # so the apiserver can reach in-cluster Services — required for admission
        # webhooks (ingress-nginx), aggregated APIs (metrics-server), and namespace
        # deletion. The taint still keeps workloads on workers; CP-node pod
        # networking works via the networkd-leaves-CNI fix (§mkGuest).
        controlPlane = true;
        clusterInit = i == 1;
        # Join via the kepler LB (fronts all 3 apiservers) for HA, not a single CP.
        serverAddr =
          if i == 1
          then null
          else "https://${hostIp}:6443";
        # apiserver cert must cover the LB + LAN admin addresses + the admin
        # domain (kubectl via k8s.pastelariadev.com -> discovery stream-proxy).
        tlsSan = [hostIp apiVip "k8s.pastelariadev.com"];
        nodeIp = "${subnet}.${toString (10 + i)}"; # .11 .12 .13
        cid = 10 + i;
        mac = "02:00:00:00:fa:0${toString i}";
        vcpu = 1; # RFC CP target (G1 tunable post-deploy)
        mem = 2048;
        disk = 8192;
      }
      else let
        i = workerIndex name;
      in {
        role = "agent";
        controlPlane = false;
        tlsSan = []; # agents don't serve the apiserver
        clusterInit = false;
        serverAddr = "https://${hostIp}:6443"; # join via the LB
        nodeIp = "${subnet}.${toString (20 + i)}"; # .21 .22 ...
        cid = 20 + i;
        mac = "02:00:00:00:fb:0${toString i}";
        vcpu = cfg.workerVcpu;
        mem = cfg.workerMem;
        disk = 20480;
      };

    mkGuest = name: let
      s = nodeSpec name;
    in {
      imports =
        [
          (mkK3sNode {
            inherit (s) role nodeIp clusterInit serverAddr controlPlane tlsSan;
            tokenFile = "/tokens/token";
          })
        ]
        # Platform baseline — declared on the clusterInit server ONLY (helm-controller
        # runs per-server; setting on >1 server conflicts). RFC §5.9.
        ++ lib.optional s.clusterInit {
          # ingress-nginx as a DaemonSet on a fixed NodePort; the kepler LB sends
          # .250:443 -> workers:30443. No in-cluster LoadBalancer.
          services.k3s.autoDeployCharts.ingress-nginx = {
            name = "ingress-nginx";
            repo = "https://kubernetes.github.io/ingress-nginx";
            version = "4.12.1";
            hash = "sha256-WfZke4wKoSJnci+greFnE/sLFqGvkyInryBl/dGn87w=";
            targetNamespace = "ingress-nginx";
            createNamespace = true;
            values.controller = {
              kind = "DaemonSet";
              service = {
                type = "NodePort";
                nodePorts = {
                  http = 30080;
                  https = ingressNodePort;
                };
              };
            };
          };
        };

      microvm = {
        hypervisor = "cloud-hypervisor";
        inherit (s) vcpu mem;
        vsock.cid = s.cid; # systemd-notify readiness over vsock
        interfaces = [
          {
            type = "tap";
            id = "vm-k3s-${name}"; # matched into br-k3s by the host (21-k3s-tap)
            inherit (s) mac;
          }
        ];
        shares = [
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
        ];
        volumes = [
          {
            image = "root.img"; # relative to /var/lib/microvms/${name}
            mountPoint = "/";
            size = s.disk;
          }
        ];
      };

      # Single NIC on the private subnet, static. Gateway is kepler.
      systemd.network.enable = true;
      systemd.network.networks."10-cluster" = {
        # Match only the real NIC, not k8s/CNI interfaces (see 99-k8s-unmanaged).
        matchConfig.Type = "ether";
        matchConfig.Kind = "!*"; # exclude virtual devices (bridges/veth/vxlan)
        networkConfig = {
          Address = "${s.nodeIp}/24";
          Gateway = hostIp;
          DHCP = "no";
        };
      };
      # CRITICAL: stop systemd-networkd from managing k3s's CNI interfaces. With
      # networkd enabled (for the static IP), it otherwise grabs cni0/veth*/flannel*
      # and breaks pod networking — cni0 goes down → "no route to host" kubelet->pod
      # and pod->service timeouts. (microvm docs warn about this for Docker veths.)
      systemd.network.networks."99-k8s-unmanaged" = {
        matchConfig.Name = ["cni0" "flannel*" "veth*" "cali*" "vxlan*" "kube-*"];
        linkConfig.Unmanaged = "yes";
      };

      # Disable the guest firewall: the nodes sit on an isolated private subnet
      # behind kepler (only .245/.250 are ever exposed, via the LB). This avoids
      # enumerating every k3s intra-cluster port (etcd/kubelet/flannel) per node.
      # Pod-level isolation is k8s NetworkPolicy (default-deny baseline), not the
      # node firewall.
      networking.firewall.enable = false;

      # SSH for admin / kubectl over the bridge (ssh -A kepler; ssh root@<nodeIp>).
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keys = sshKeys;

      system.stateVersion = "25.11";
    };
  in {
    imports = [inputs.microvm.nixosModules.host];

    options.kepler.k3s = {
      enable = lib.mkEnableOption "k3s test cluster (microvm nodes) on kepler";
      workerCount = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of worker (agent) microvm nodes. Scale: bump + switch.";
      };
      workerMem = lib.mkOption {
        type = lib.types.int;
        default = 16384;
        description = "RAM (MiB) per worker. 16 GB; with 2 workers that's 32 GB + 6 GB CP on kepler's 62 GB (ARC yields under pressure). More headroom after the 128 GB upgrade.";
      };
      workerVcpu = lib.mkOption {
        type = lib.types.int;
        default = 2;
      };
    };

    config = lib.mkIf cfg.enable {
      # Private bridge; kepler is the gateway (no physical NIC enslaved → invisible
      # to the LAN, RFC §5.3). enp5s0 DHCP is rendered to networkd from the legacy
      # option, so LAN/SSH is preserved. ⚠ supervised deploy.
      networking.useNetworkd = true;

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

      networking.firewall.trustedInterfaces = ["br-k3s"];

      # NAT egress for the private cluster subnet (RFC §5.3 option B: kepler is
      # gateway + NAT). Without it, pods/coredns can't reach upstream DNS or pull
      # anything not baked. Masquerade br-k3s -> enp5s0.
      networking.nat = {
        enable = true;
        internalInterfaces = ["br-k3s"];
        externalInterface = "enp5s0";
      };

      # --- kepler L4 load-balancer (RFC §5.3 / §10b): the one host that's
      # mandatory anyway fronts the cluster. nginx stream (TCP passthrough) — no
      # in-cluster kube-vip/MetalLB. Publishes two LAN IPs + a private registration
      # address. Headless CP apiservers are the backend.
      networking.interfaces.enp5s0.ipv4.addresses = [
        {
          address = apiVip;
          prefixLength = 24;
        }
        {
          address = ingressVip;
          prefixLength = 24;
        }
      ];
      networking.firewall.allowedTCPPorts = [6443 443];

      services.nginx = {
        enable = true;
        # TCP passthrough; apiserver does its own mTLS so we must NOT terminate.
        streamConfig = ''
          upstream k3s-apiserver {
          ${cpServers}
          }
          upstream k3s-ingress {
          ${workerServers}
          }
          # Listen on all interfaces so the endpoints answer on the LAN (.245/.250
          # aliases + private 10.250.0.1 registration) AND kepler's Tailscale IP —
          # discovery's SWAG is on a different physical LAN and reaches kepler only
          # over the tailnet (RFC §5.3 / 4d).
          server { listen 6443; proxy_pass k3s-apiserver; proxy_timeout 600s; }
          server { listen 443; proxy_pass k3s-ingress; proxy_timeout 600s; }
        '';
      };

      # Shared join token, provisioned host-side before any node starts.
      systemd.services.k3s-cluster-token = {
        description = "Provision the k3s cluster join token";
        wantedBy = ["multi-user.target"];
        before = map (n: "microvm@${n}.service") allNames;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p ${tokenDir}
          if [ ! -s ${tokenDir}/token ]; then
            umask 077
            head -c 32 /dev/urandom | base64 > ${tokenDir}/token
          fi
        '';
      };

      microvm.autostart = allNames;
      microvm.vms = lib.genAttrs allNames (name: {config = mkGuest name;});

      # Stability: the microvm@ unit is Type=notify with a 150s default start
      # timeout. On a cold/contended boot (host reboot or `switch` restarting the 3
      # CPs together) the guest's vsock ready-notify can land past 150s, failing the
      # unit and leaving it "activating" until a manual restart. Give it headroom so
      # boots self-heal (Restart=always handles the rest). Applies to all microvms.
      systemd.services."microvm@".serviceConfig.TimeoutStartSec = 300;
    };
  };
}
