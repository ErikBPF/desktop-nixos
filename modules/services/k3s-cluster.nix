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
}
