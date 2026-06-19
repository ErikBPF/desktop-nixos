{inputs, ...}: let
  # The nixosTest needs a concrete pkgs for the build platform. The test runs in
  # CI / locally, never on a target host, so pinning x86_64-linux is fine.
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  mkK3sNode = import ./_k3s-node.nix;

  # Test-only join token. The real cluster never uses a literal token — it points
  # tokenFile at a host-provisioned path (RFC §5.5). Plaintext is fine in a
  # sandboxed VM test.
  testToken = "smoke-test-shared-token-not-for-real-use";

  # Wrap the shared node config with test-harness bits: the node IP comes from
  # the test driver (primaryIPAddress on the eth1 VLAN), the token is the literal
  # test token, and we drop the firewall + size the VM for the sandbox.
  mkTestNode = args: {
    config,
    lib,
    ...
  }: {
    imports = [
      (mkK3sNode (args
        // {
          nodeIp = config.networking.primaryIPAddress;
          iface = "eth1";
          token = testToken;
        }))
    ];
    networking.firewall.enable = false;
    virtualisation = {
      cores = 2;
      memorySize = 2048;
      diskSize = 8192;
    };
  };
in {
  # TDD green gate (RFC §5.10): boot a minimal cluster in QEMU and assert it forms
  # offline, before any byte touches kepler. Build/run with:
  #   nix build .#checks.x86_64-linux.k3s-smoke -L
  flake.checks.x86_64-linux.k3s-smoke = pkgs.testers.runNixOSTest {
    name = "k3s-smoke";

    nodes = {
      server = mkTestNode {
        role = "server";
        clusterInit = true;
      };
      agent = mkTestNode {
        role = "agent";
        serverAddr = "https://server:6443";
      };
    };

    testScript = ''
      start_all()
      server.wait_for_unit("k3s")
      agent.wait_for_unit("k3s")

      # Wait until BOTH nodes exist AND are Ready. The agent join is async, so we
      # poll for a count of 2 — proves etcd, the agent join token, and flannel
      # (from baked images) all work offline. (grep ' Ready ' won't match NotReady.)
      server.wait_until_succeeds(
          "test $(k3s kubectl get nodes --no-headers | grep -c ' Ready ') -eq 2",
          timeout=300,
      )

      # A system pod from a baked image actually schedules and goes Ready —
      # proves scheduling + image availability + CNI end to end, no network.
      server.wait_until_succeeds(
          "k3s kubectl -n kube-system wait --for=condition=Ready "
          "pod -l k8s-app=kube-dns --timeout=180s",
          timeout=300,
      )
    '';
  };

  # Full-topology check (RFC §5.10): 3-server embedded-etcd HA control plane +
  # a worker, control-plane tainted. Validates the task-4 k3s config (etcd
  # quorum, joining servers, dedicated-CP taint) in QEMU — independent of the
  # kepler microvm plumbing. Heavier (4 VMs); run on-demand:
  #   nix build .#checks.x86_64-linux.k3s-ha -L
  flake.checks.x86_64-linux.k3s-ha = pkgs.testers.runNixOSTest {
    name = "k3s-ha";

    nodes = {
      cp1 = mkTestNode {
        role = "server";
        clusterInit = true;
        controlPlane = true;
      };
      cp2 = mkTestNode {
        role = "server";
        serverAddr = "https://cp1:6443";
        controlPlane = true;
      };
      cp3 = mkTestNode {
        role = "server";
        serverAddr = "https://cp1:6443";
        controlPlane = true;
      };
      w1 = mkTestNode {
        role = "agent";
        serverAddr = "https://cp1:6443";
      };
    };

    testScript = ''
      start_all()
      for m in [cp1, cp2, cp3, w1]:
          m.wait_for_unit("k3s")

      # All 4 nodes Ready — the 3 servers form a 3-member embedded-etcd quorum
      # and the agent joins.
      cp1.wait_until_succeeds(
          "test $(k3s kubectl get nodes --no-headers | grep -c ' Ready ') -eq 4",
          timeout=420,
      )
      # Exactly 3 control-plane nodes.
      cp1.succeed(
          "test $(k3s kubectl get nodes -l node-role.kubernetes.io/control-plane "
          "--no-headers | wc -l) -eq 3"
      )
      # The NoSchedule taint is applied to a control-plane node and absent on the
      # worker — proves the dedicated-CP separation (RFC §3.3).
      cp1.succeed(
          "k3s kubectl get node cp1 -o jsonpath='{.spec.taints[*].key}' "
          "| grep -q node-role.kubernetes.io/control-plane"
      )
      cp1.fail(
          "k3s kubectl get node w1 -o jsonpath='{.spec.taints[*].key}' "
          "| grep -q node-role.kubernetes.io/control-plane"
      )
    '';
  };
}
