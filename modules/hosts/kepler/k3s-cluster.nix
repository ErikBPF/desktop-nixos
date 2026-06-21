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
  fleetUser = config.username; # flake-parts top-level options (meta.nix)
  inherit (config) domain;
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

    # etcd snapshots land here (kepler's bulk-pool ZFS, /bulk) via a per-CP
    # virtiofs share — survives guest root.img loss. RFC §13.
    etcdSnapshotBase = "/bulk/k3s-etcd-snapshots";

    # Fleet observability: ship cluster pod logs to discovery's Loki — the same
    # sink the host Alloy uses, but addressed by raw tailnet IP, not MagicDNS:
    # pods aren't tailnet members so "discovery" doesn't resolve in-cluster (the
    # host Alloy in modules/services/alloy.nix uses the name). Keep the IP in sync.
    discoveryLokiUrl = "http://100.76.140.121:3100/loki/api/v1/push";
    clusterName = lib.head (lib.splitString "." domain); # "pastelariadev"

    # In-cluster Alloy DaemonSet config: tail pod logs via the k8s API (not host
    # files → no hostPath, stays PodSecurity-baseline clean) and forward to Loki,
    # keeping only this node's pods (DaemonSet → one Alloy per node).
    alloyConfig = ''
      discovery.kubernetes "pods" {
        role = "pod"
      }

      discovery.relabel "pod_logs" {
        targets = discovery.kubernetes.pods.targets
        // NODE_NAME from the downward API (alloy.extraEnv) — keep local pods only.
        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          regex         = sys.env("NODE_NAME")
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }
        // Stream labels stay low-cardinality: namespace, app, container. Pod name
        // is deliberately NOT a label — its per-restart ReplicaSet hash mints a new
        // Loki stream every restart (cardinality blowup; telemetry RFC §1). Filter
        // by namespace/container + line content; promote to structured metadata if
        // per-pod querying is ever needed.
        rule {
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
          target_label  = "app"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }
      }

      loki.source.kubernetes "pods" {
        targets    = discovery.relabel.pod_logs.output
        forward_to = [loki.write.discovery.receiver]
      }

      loki.write "discovery" {
        endpoint {
          url = "${discoveryLokiUrl}"
        }
        external_labels = { "cluster" = "${clusterName}" }
      }
    '';

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
        # domain (kubectl via k8s.${domain} -> discovery stream-proxy).
        tlsSan = [hostIp apiVip "k8s.${domain}"];
        nodeIp = "${subnet}.${toString (10 + i)}"; # .11 .12 .13
        cid = 10 + i;
        mac = "02:00:00:00:fa:0${toString i}";
        # etcd is memory + fsync sensitive; 2G/1vcpu flapped under sync load
        # (grill §3). 4G/2vcpu gives etcd+apiserver headroom. 3×4G+2×16G on 62G.
        vcpu = 2;
        mem = 4096;
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
            etcdSnapshotDir =
              if s.controlPlane
              then "/etcd-snapshots"
              else null;
          })
        ]
        # Platform baseline — declared on ALL servers. NixOS bakes the chart as a
        # STATIC tarball in each server's /static/charts; the helm-install job hits
        # an arbitrary apiserver, so the tarball must exist on every server or
        # upgrades 404 (a clusterInit-only chart installs once, then can never
        # upgrade). Identical Nix manifests across servers = no conflict (k3s only
        # warns about *manual* drift). RFC §5.9 / §13.
        ++ lib.optional (s.role == "server") {
          services.k3s.autoDeployCharts = {
            # ingress-nginx as a DaemonSet on a fixed NodePort; the kepler LB sends
            # .250:443 -> workers:30443. No in-cluster LoadBalancer.
            # (Traefik cutover deferred — orion build host was down, blocking the
            # deploy mid-flight; redo it in a maintenance window with orion up.)
            ingress-nginx = {
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

            # Grafana Alloy DaemonSet → ships pod logs to discovery's Loki.
            # repo mode (not `package`): a baked static chart lands only on cp-1's
            # /static/charts, but the helm-install job hits any of the 3 apiservers
            # → 404 on cp-2/cp-3. helm-controller pulls from the repo index at job
            # time (NAT egress resolves the GitHub-release tgz), like ingress-nginx.
            alloy = {
              name = "alloy";
              repo = "https://grafana.github.io/helm-charts";
              version = "1.10.0";
              hash = "sha256-q8ceioRgZbSPD5g73De4nEZWkPF5fD3zFN7kxQGdtdU=";
              targetNamespace = "monitoring";
              createNamespace = true;
              values = {
                controller = {
                  type = "daemonset";
                  # Run on every node incl. the NoSchedule-tainted control planes,
                  # so CP-scheduled pod logs are captured too (a log collector
                  # should tolerate all taints).
                  tolerations = [{operator = "Exists";}];
                };
                alloy = {
                  configMap.content = alloyConfig;
                  # Node name for the per-node log-keep filter (downward API).
                  extraEnv = [
                    {
                      name = "NODE_NAME";
                      valueFrom.fieldRef.fieldPath = "spec.nodeName";
                    }
                  ];
                  # API-based log tailing → no /var/log host mount needed.
                  mounts.varlog = false;
                  resources.requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
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
          # CP nodes write embedded-etcd snapshots to a host-backed /bulk subdir.
          ++ lib.optional s.controlPlane {
            tag = "etcd-snap";
            source = "${etcdSnapshotBase}/${name}";
            mountPoint = "/etcd-snapshots";
            proto = "virtiofs";
          };
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
        # Pods also need discovery's observability stack, which is tailnet-only.
        # Masquerade the cluster subnet onto tailscale0 so Tailscale accepts the
        # egress (source becomes kepler's own TS IP) — push-only, nothing routes
        # back into the pods, so no subnet-route advertisement is needed. iptables
        # backend (no networking.nftables on the fleet).
        extraCommands = ''
          iptables -t nat -A POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE
        '';
        extraStopCommands = ''
          iptables -t nat -D POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE 2>/dev/null || true
        '';
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

      microvm.autostart = allNames;
      microvm.vms = lib.genAttrs allNames (name: {config = mkGuest name;});

      systemd.services =
        {
          # Provision host-side state before any node starts: the shared join
          # token + the per-CP etcd-snapshot share sources. `before = microvm@*`
          # guarantees the dirs exist before virtiofsd opens them. (tmpfiles can't
          # make these: /bulk is owned by the fleet user and tmpfiles refuses to
          # descend a non-root parent to create root dirs — "unsafe path
          # transition". Plain mkdir as root has no such qualm.) RFC §13.
          k3s-cluster-token = {
            description = "Provision the k3s join token + etcd-snapshot dirs";
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

              for d in ${lib.concatMapStringsSep " " (n: "${etcdSnapshotBase}/${n}") cpNames}; do
                mkdir -p "$d" && chmod 700 "$d"
              done
            '';
          };

          # Stability: the microvm@ unit is Type=notify with a 150s default start
          # timeout. On a cold/contended boot (host reboot or `switch` restarting the
          # 3 CPs together) the guest's vsock ready-notify can land past 150s, failing
          # the unit and leaving it "activating" until a manual restart. Give it
          # headroom so boots self-heal (Restart=always handles the rest).
          "microvm@".serviceConfig.TimeoutStartSec = 300;
        }
        # Stagger cold boot to cut the simultaneous-boot vsock-notify contention:
        # cp-1 first (clusterInit), then cp-2 → cp-3 serially (clean sequential etcd
        # join), workers after cp-1 (apiserver is up so they join immediately).
        # Drop-ins on the template instances; After= is ordering-only (no failure
        # cascade if a predecessor dies).
        // lib.mapAttrs' (name: pred:
          lib.nameValuePair "microvm@${name}" {
            overrideStrategy = "asDropin";
            after = ["microvm@${pred}.service"];
          }) ({
            "cp-2" = "cp-1";
            "cp-3" = "cp-2";
          }
          // lib.genAttrs workerNames (_: "cp-1"));
    };
  };
}
