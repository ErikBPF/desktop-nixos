# Reusable k3s node config, role-parameterized. NOT auto-imported (leading `_`);
# imported explicitly by both the nixosTest (services/k3s-cluster.nix) and the
# real microvm guests (hosts/kepler/…), so one definition drives both. RFC §5.5.
{
  role, # "server" | "agent"
  nodeIp, # node IP on the cluster network (k3s --node-ip)
  clusterInit ? false, # first server bootstraps embedded etcd
  serverAddr ? null, # joining servers/agents point here
  controlPlane ? false, # taint NoSchedule (dedicated control plane)
  tlsSan ? [], # extra apiserver cert SANs (LB / LAN IPs) — servers only
  etcdSnapshotDir ? null, # relocate etcd snapshots here (servers only) — e.g. a host-backed share
  iface ? null, # flannel iface — only needed to disambiguate multi-NIC nodes
  token ? null, # literal token — test only
  tokenFile ? null, # file path — real cluster (host-provisioned, RFC §5.5)
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  # PodSecurity admission baseline (RFC §5.8): blocks the genuinely dangerous
  # (privileged, host namespaces/ports, hostPath) cluster-wide while letting
  # ordinary test charts run. kube-system + ingress-nginx exempt (they need
  # elevated access). Tighten the default to `restricted` per-namespace to test
  # hardening. apiserver reads this /nix/store path (guest shares the host store).
  psaConfig = pkgs.writeText "psa.yaml" ''
    apiVersion: apiserver.config.k8s.io/v1
    kind: AdmissionConfiguration
    plugins:
    - name: PodSecurity
      configuration:
        apiVersion: pod-security.admission.config.k8s.io/v1
        kind: PodSecurityConfiguration
        defaults:
          enforce: baseline
          enforce-version: latest
          audit: baseline
          audit-version: latest
          warn: baseline
          warn-version: latest
        exemptions:
          usernames: []
          runtimeClasses: []
          namespaces: [kube-system, ingress-nginx]
  '';
in {
  # k8s node prerequisite: bridged pod traffic must traverse iptables so
  # kube-proxy can NAT pod -> ClusterIP. The minimal microvm guest doesn't load
  # br_netfilter / set these by default, so pod->service times out (node->service
  # works). (NixOS test-driver VMs have these, which is why the nixosTest passed.)
  boot.kernelModules = ["br_netfilter" "overlay"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  services.k3s = {
    enable = true;
    inherit role clusterInit;
    token = lib.mkIf (token != null) token;
    tokenFile = lib.mkIf (tokenFile != null) tokenFile;
    serverAddr = lib.mkIf (serverAddr != null) serverAddr;
    # Drop traefik — the cluster brings its own ingress (RFC §5.5/§5.9), and
    # k3s's bundled traefik helm-install can't run offline anyway.
    disable = lib.optionals (role == "server") ["traefik"];
    # Bake the airgap image bundle into the node closure so nodes pull nothing at
    # runtime — mandatory offline in the nixosTest (§5.10/G5), air-gap-capable on
    # kepler (§5.9).
    images = [config.services.k3s.package."airgap-images-amd64-tar-zst"];
    extraFlags =
      # --node-ip pins the node IP (k3s otherwise picks the default-route iface).
      ["--node-ip=${nodeIp}"]
      # Server-only, cluster-wide settings: flannel host-gw (all nodes share one L2
      # bridge — VXLAN over virtio NICs drops encapsulated packets → "no route to
      # host"/flaky pod→svc), PodSecurity baseline admission, and apiserver SANs.
      ++ lib.optionals (role == "server") (
        [
          "--flannel-backend=host-gw"
          "--kube-apiserver-arg=admission-control-config-file=${psaConfig}"
          # Expose embedded-etcd metrics on :2381 (0.0.0.0) so the in-cluster
          # alloy-metrics scrape can reach etcd health/perf series.
          "--etcd-expose-metrics=true"
        ]
        ++ map (s: "--tls-san=${s}") tlsSan
        # Relocate embedded-etcd snapshots off the guest's ephemeral root.img onto
        # a host-backed share (default cadence: every 12h, retain 5). Filenames
        # carry the node name, so all servers can target one host tree (RFC §13).
        ++ lib.optionals (etcdSnapshotDir != null) ["--etcd-snapshot-dir=${etcdSnapshotDir}"]
      )
      # --flannel-iface only needed to disambiguate multi-NIC nodes (the test VLAN).
      ++ lib.optionals (iface != null) ["--flannel-iface=${iface}"]
      ++ lib.optionals controlPlane ["--node-taint=node-role.kubernetes.io/control-plane:NoSchedule"];
  };
}
