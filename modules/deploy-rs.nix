# deploy-rs remote-deploy wiring (flake-parts module).
#
# Exposes the top-level `flake.deploy.nodes.<host>` output that deploy-rs keys
# off. Subsequent switches only — first install stays nixos-anywhere/nixos-infect
# (see justfile `deploy-*`/`infect-voyager`). The recipe is `just deploy-rs <host>`;
# the legacy `switch-<host>`/`deploy` recipes stay as the escape hatch.
#
# Design (per the reviewed RFC 2026-06-30-deploy-rs-as-deploy-standard.md):
#
#   * Addressing is read from the fleet SSOT — never hardcoded. Public OCI
#     guests deploy over their stable Tailscale addresses; LAN hosts keep their
#     primary addresses.
#
#   * Per-host activation is selected from the host's OWN system:
#     `deploy-rs.lib.${system}.activate.nixos`, with `system` taken from the built
#     nixosConfiguration's `pkgs.stdenv.hostPlatform.system`. x86 hosts resolve to x86_64-linux,
#     archinaut (aarch64) to aarch64-linux automatically. mkNode does NOT hardcode
#     a system.
#
#   * deploy-rs's `deployChecks` is deliberately NOT wired into perSystem.checks /
#     `nix flake check`. deployChecks builds every node's full activation closure
#     (incl. aarch64 via binfmt), which would be a large, redundant CI-time cost on
#     top of the toplevel builds `modules/configurations.nix` already exposes as
#     checks. Default `nix flake check` / `just dry-all` cost is unchanged. If you
#     ever want the deploy-output shape validated, run it explicitly, opt-in:
#       nix build .#deployChecks.<system> -L
#     (left commented below so it is never on by default).
#
#   * magicRollback (activate → re-open SSH to confirm reachability → auto-revert
#     on failure) is set per node by its REACH PATH, because the connectivity
#     re-check races slow first-boot units (sops-nix decrypts during activation;
#     Tailscale/compose come up after):
#       - primary-IP sshd path → magicRollback = true. sshd is independent of sops,
#         so the re-check succeeds as soon as the new generation's sshd is up.
#       - tailnet-only reach   → magicRollback = false. The re-check can run
#         before tailscaled (post-activation, sops-gated) is back, false-reverting
#         a good deploy. autoRollback (activation-failure-only) still applies.
#     Timeouts are bounded generously to tolerate a slow activation without the
#     confirmation firing early.
{
  inputs,
  config,
  lib,
  ...
}: let
  fleet = config.flake.fleet;
  nixosConfigs = config.flake.nixosConfigurations;

  # Build the activation profile for a host using deploy-rs's lib keyed on the
  # host's OWN platform (x86_64-linux / aarch64-linux), derived from the built
  # nixosConfiguration. Never hardcodes a system.
  activate = host: let
    nixos = nixosConfigs.${host};
    system = nixos.pkgs.stdenv.hostPlatform.system;
  in
    inputs.deploy-rs.lib.${system}.activate.nixos nixos;

  # One deploy node. `hostname` comes from the fleet SSOT. ssh as erik@2222,
  # activate as root (sudo) — matches today's `--sudo` / port-2222 model.
  #
  #   magicRollback:      true for primary-IP reach, false for tailnet-only.
  #   activationTimeout:  seconds to wait for activation to finish.
  #   confirmTimeout:     seconds the post-activation reachability re-check waits.
  mkNode = {
    host,
    magicRollback,
    tailnetOnly ? false,
    activationTimeout ? 300,
    confirmTimeout ? 60,
  }: {
    hostname =
      fleet.hosts.${
        host
      }.${
        if tailnetOnly
        then "tailscaleIp"
        else "ip"
      };
    sshUser = "erik";
    user = "root";
    sshOpts = ["-p" "2222"];
    inherit magicRollback activationTimeout confirmTimeout;
    profiles.system.path = activate host;
  };
in {
  # Remote NixOS fleet only. The Ubuntu laptop and Home Assistant OS are out.
  flake.deploy.nodes = {
    # Public Oracle guests are reachable only through Tailscale. Generous
    # activationTimeout: the 1 GB micro activates slowly.
    voyager = mkNode {
      host = "voyager";
      tailnetOnly = true;
      magicRollback = false;
      activationTimeout = 600;
      confirmTimeout = 60;
    };

    # telstar: public projects host (Oracle A1, aarch64). Its tailnet address is
    # null until the capacity-retry provisioner lands and enrolls it.
    telstar = mkNode {
      host = "telstar";
      tailnetOnly = true;
      magicRollback = false;
      activationTimeout = 600;
    };

    # vanguard: 2nd Oracle Always-Free AMD micro, multi-role offsite node
    # (docs/proposals/2026-07-10-vanguard-second-oracle-node.md). Sibling of
    # voyager; reached through its stable tailnet address.
    vanguard = mkNode {
      host = "vanguard";
      tailnetOnly = true;
      magicRollback = false;
      activationTimeout = 600;
    };

    # LAN hosts reached on their LAN IP via sshd (sops-independent) → magic
    # rollback safe. A keyboard is reachable, but auto-revert still beats a
    # manual recovery trip.
    discovery = mkNode {
      host = "discovery";
      magicRollback = true;
      # Harbor version reconciles may pull and migrate during activation.
      activationTimeout = 1800;
    };
    orion = mkNode {
      host = "orion";
      magicRollback = true;
    };

    # Pathfinder's LAN route is unavailable from the deploy controller; use its
    # stable tailnet address and the same activation-only rollback as other
    # tailnet-only hosts.
    pathfinder = mkNode {
      host = "pathfinder";
      tailnetOnly = true;
      magicRollback = false;
    };

    # kepler: LAN-IP/sshd reach → magic rollback safe. Deploy on its own window
    # (out of any fan-out) so the AI serving stack isn't restarted as a side
    # effect — deploy-rs doesn't change that; invoke `just deploy-rs kepler`
    # deliberately.
    kepler = mkNode {
      host = "kepler";
      magicRollback = true;
    };
    apollo = mkNode {
      host = "apollo";
      magicRollback = true;
    };

    # archinaut: aarch64 RPi (activate.nixos resolves to aarch64-linux via
    # pkgs.system; closure still builds on orion through binfmt). Reached on its
    # WiFi LAN IP via sshd → magic rollback safe. WiFi can be slow to settle, so
    # a longer activationTimeout.
    archinaut = mkNode {
      host = "archinaut";
      magicRollback = true;
      activationTimeout = 600;
    };

    # drtest: THROWAWAY deploy-rs proof-of-concept VM running on orion.
    # NOT a real fleet host — no sops, no tailscale, no fleet IP.
    # QEMU usermode hostfwd maps orion:2224 → VM:2222 (sshd).
    # deploy-rs targets orion's LAN IP at port 2224; magicRollback=true so a
    # generation that breaks SSH auto-reverts — that's the test.
    # Lifecycle: start with `just drtest-vm-start`, remove with `just drtest-vm-stop`.
    drtest = let
      nixos = config.flake.nixosConfigurations.drtest;
      system = nixos.pkgs.stdenv.hostPlatform.system;
    in {
      hostname = fleet.hosts.orion.ip; # reach via orion (VM hostfwd'd there)
      sshUser = "erik";
      user = "root";
      sshOpts = ["-p" "2224"]; # orion:2224 → VM:2222 via QEMU hostfwd
      magicRollback = true;
      activationTimeout = 120;
      confirmTimeout = 30;
      profiles.system.path = inputs.deploy-rs.lib.${system}.activate.nixos nixos;
    };
  };

  # Opt-in only — NOT wired into perSystem.checks (would build every host's full
  # activation closure in `nix flake check`/CI). Run explicitly when you want the
  # deploy output shape validated:
  #   nix build .#deployChecks.<system> -L
  flake.deployChecks =
    lib.mapAttrs
    (system: deployLib: deployLib.deployChecks config.flake.deploy)
    inputs.deploy-rs.lib;

  # Pin the deploy-rs CLI from the flake input so `just deploy-rs <host>` runs the
  # flake.lock-locked tool (`nix run .#deploy-rs`), not a floating `nix run github:…`.
  perSystem = {system, ...}: {
    packages.deploy-rs = inputs.deploy-rs.packages.${system}.default;
  };
}
