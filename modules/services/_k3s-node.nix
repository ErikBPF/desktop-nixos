# Reusable k3s node config, role-parameterized. NOT auto-imported (leading `_`);
# imported explicitly by both the nixosTest (services/k3s-cluster.nix) and the
# real microvm guests (hosts/kepler/…), so one definition drives both. RFC §5.5.
{
  role, # "server" | "agent"
  nodeIp, # node IP on the cluster network (k3s --node-ip)
  clusterInit ? false, # first server bootstraps embedded etcd
  serverAddr ? null, # joining servers/agents point here
  controlPlane ? false, # taint NoSchedule (dedicated control plane)
  iface ? null, # flannel iface — only needed to disambiguate multi-NIC nodes
  token ? null, # literal token — test only
  tokenFile ? null, # file path — real cluster (host-provisioned, RFC §5.5)
}: {
  config,
  lib,
  ...
}: {
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
    # Pin k3s to a known node IP. Without --node-ip k3s auto-picks the
    # default-route iface, which on a multi-NIC node is the wrong one.
    # --flannel-iface is only needed when more than one NIC exists (the test VLAN
    # case); single-NIC microvm guests auto-detect correctly.
    extraFlags =
      ["--node-ip=${nodeIp}"]
      ++ lib.optionals (iface != null) ["--flannel-iface=${iface}"]
      ++ lib.optionals controlPlane ["--node-taint=node-role.kubernetes.io/control-plane:NoSchedule"];
  };
}
