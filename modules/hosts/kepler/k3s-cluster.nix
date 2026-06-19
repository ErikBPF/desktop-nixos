# k3s test cluster on kepler — each node a NixOS MicroVM.
# See docs/proposals/2026-06-19-kepler-k3s-microvm-cluster.md.
#
# STAGE 1 (this file): single throwaway control-plane VM (cp-1, clusterInit) to
# prove the microvm plumbing on real hardware — cloud-hypervisor + virtiofs /nix
# + tap on a private bridge + k3s comes up offline (airgap images baked). NOT the
# full topology yet (no workers, no LB, no fan-out — those follow once this boots).
#
# Gated behind `kepler.k3s.enable` (default off) so importing it is inert; the VM
# only runs after `kepler.k3s.enable = true` + a switch. The networkd switch is
# connectivity-sensitive — deploy this supervised (console), not blind over SSH.
{inputs, ...}: {
  flake.modules.nixos.kepler-k3s-cluster = {
    config,
    lib,
    ...
  }: let
    cfg = config.kepler.k3s;
    mkK3sNode = import ../../services/_k3s-node.nix;

    subnet = "10.250.0";
    hostIp = "${subnet}.1"; # kepler's address on the private bridge / cluster gateway
    cp1Ip = "${subnet}.11";

    # Host-side token dir, shared read-only into the guest via virtiofs (RFC §5.5,
    # G3: guests run no sops). /var/lib is btrfs on kepler — safe for a virtiofs
    # share (the ZFS xattr=sa caveat only applies to ZFS-backed shares).
    tokenDir = "/var/lib/k3s-cluster";
    tokenFile = "${tokenDir}/token";
  in {
    # Host capability is harmless when no VMs are defined; imports can't be gated
    # on config, so this stays unconditional.
    imports = [inputs.microvm.nixosModules.host];

    options.kepler.k3s.enable =
      lib.mkEnableOption "k3s test cluster (microvm nodes) on kepler";

    config = lib.mkIf cfg.enable {
      # --- Private bridge for cluster nodes; kepler is the gateway (no physical
      # NIC enslaved → invisible to the LAN, RFC §5.3 option B). Requires
      # systemd-networkd. kepler's enp5s0 DHCP is rendered to networkd from the
      # legacy networking.interfaces option, so LAN/SSH is preserved. ⚠ supervised
      # deploy — a networkd misconfig drops SSH.
      networking.useNetworkd = true;

      systemd.network = {
        netdevs."20-br-k3s".netdevConfig = {
          Name = "br-k3s";
          Kind = "bridge";
        };
        networks."20-br-k3s" = {
          matchConfig.Name = "br-k3s";
          # kepler owns the subnet gateway IP; its own default route stays on enp5s0.
          address = ["${hostIp}/24"];
          # The bridge has no carrier until a VM tap attaches; don't let it (or the
          # taps) fail systemd-networkd-wait-online and leave the host "degraded".
          linkConfig.RequiredForOnline = "no";
        };
        # Enslave the microvm tap(s) into the bridge as they appear.
        networks."21-k3s-tap" = {
          matchConfig.Name = "vm-k3s-*";
          networkConfig.Bridge = "br-k3s";
          linkConfig.RequiredForOnline = "no";
        };
      };

      # Bridge traffic is intra-cluster; don't let the host firewall block it.
      networking.firewall.trustedInterfaces = ["br-k3s"];

      # Generate the shared join token once, before the VM starts. Host-only;
      # 0600. (Real cluster: sops — for a disposable LAN sandbox a generated
      # secret is sufficient, RFC §5.5.)
      systemd.services.k3s-cluster-token = {
        description = "Provision the k3s cluster join token";
        wantedBy = ["multi-user.target"];
        before = ["microvm@cp-1.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p ${tokenDir}
          if [ ! -s ${tokenFile} ]; then
            umask 077
            head -c 32 /dev/urandom | base64 > ${tokenFile}
          fi
        '';
      };

      microvm.autostart = ["cp-1"];

      microvm.vms.cp-1.config = {
        imports = [
          (mkK3sNode {
            role = "server";
            clusterInit = true;
            nodeIp = cp1Ip;
            tokenFile = "/tokens/token";
            # NOT control-plane-tainted: single node must stay schedulable so
            # coredns/etc. run. Taints come with the full topology (workers exist).
          })
        ];

        microvm = {
          hypervisor = "cloud-hypervisor";
          # RFC target CP size is 1 vCPU / 2 GB (G1, tunable post-deploy); give the
          # proof a little headroom for the first-boot image import.
          vcpu = 2;
          mem = 2048;
          # vsock enables cloud-hypervisor systemd-notify, so microvm@cp-1 reports
          # ready when the guest is actually up. Unique CID per VM.
          vsock.cid = 11;

          interfaces = [
            {
              type = "tap";
              id = "vm-k3s-cp1"; # matched into br-k3s by the host (21-k3s-tap)
              mac = "02:00:00:00:fa:01";
            }
          ];

          shares = [
            {
              # Share the host store so the guest image stays tiny (RFC §5.4).
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
              image = "/var/lib/microvms/cp-1/root.img";
              mountPoint = "/";
              size = 8192;
            }
          ];
        };

        # Single NIC on the private subnet, static. Gateway is kepler; no NAT in
        # stage 1 — the node forms offline from the baked airgap images.
        systemd.network.enable = true;
        systemd.network.networks."10-cluster" = {
          matchConfig.Type = "ether";
          networkConfig = {
            Address = "${cp1Ip}/24";
            Gateway = hostIp;
            DHCP = "no";
          };
        };

        system.stateVersion = "25.11";
      };
    };
  };
}
