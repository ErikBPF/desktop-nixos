# OpenBao Raft witness / 3rd voter (R4, docs/proposals/
# 2026-07-10-vanguard-second-oracle-node.md).
#
# ============================================================================
# HIGHER-RISK, LAST-PHASE ROLE. READ ALL OF THIS BEFORE EVER FLIPPING
# services.vaultWitness.enable TO true.
#
#   1. WAN Raft-write latency is UNPROVEN. Every OpenBao quorum WRITE would
#      need a round-trip to São Paulo <-> home before committing (Raft is
#      fsync/latency-sensitive). A slow or flaky home uplink could stall
#      writes fleet-wide, not just for vanguard. Prove this with a latency
#      test (proposal §R4/enablement phase 3) before enabling.
#   2. discovery's cluster_addr (modules/hosts/discovery/vault.nix) is
#      currently `http://127.0.0.1:8201` — LOOPBACK. A 3rd voter cannot reach
#      a loopback cluster_addr from off-site. Moving it to a real address is a
#      discovery-side change THIS MODULE DELIBERATELY DOES NOT MAKE — that is
#      a separate, deliberate, human-reviewed edit to that file, with its own
#      TLS decision, made only when R4 is actually being enabled.
#   3. retryJoinAddr below is a PLACEHOLDER pointing at discovery's current
#      (wrong, loopback) cluster_addr — on purpose, so this cannot silently
#      "just work" without (2) being done first. TLS is also unresolved
#      (tls_disable = true below matches discovery's current loopback/tailnet
#      listeners, but a WAN join is a different exposure — revisit).
#   4. With discovery as the only on-prem voter, enabling this would put 2 of
#      3 voters offsite — a home-uplink outage would leave quorum ALIVE but
#      unable to serve on-prem consumers. Understand this trade before
#      enabling.
#
# THIS FILE, AS SHIPPED:
#   - services.vaultWitness.enable defaults to FALSE.
#   - When false (default): options only. No package, no service, no port, no
#     assumption about discovery. A total no-op — `lib.mkIf cfg.enable` gates
#     every line below.
#   - When true: scaffolds openbao.settings.storage.raft for THIS host only
#     (node_id, retry_join at the placeholder address). It is NOT a working
#     witness as shipped — retryJoinAddr must be corrected (2) and a latency
#     test (1) run first. The gate exists so the remaining gaps are an
#     explicit option to fix, not a silent assumption.
#   - discovery's own modules/hosts/discovery/vault.nix is NEVER touched by
#     this file.
# ============================================================================
_: {
  flake.modules.nixos.vault-witness = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.vaultWitness;
  in {
    options.services.vaultWitness = {
      enable = lib.mkEnableOption "the OpenBao Raft witness/3rd-voter — HIGHER RISK, defaults to false; read the file header (docs/proposals/2026-07-10-vanguard-second-oracle-node.md §R4) before enabling. Requires a WAN-latency test and a separate, deliberate discovery-side cluster_addr/retry_join/TLS change first";

      retryJoinAddr = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "http://127.0.0.1:8201"; # PLACEHOLDER: discovery's CURRENT (loopback) cluster_addr — deliberately wrong until §R4-2 is done.
        description = ''
          discovery's cluster_addr, as it would need to be AFTER the (not yet
          made) discovery-side change described in this file's header. Left at
          the current, unreachable-from-offsite value on purpose.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.openbao];

      services.openbao = {
        enable = true;
        settings = {
          listener.default = {
            type = "tcp";
            address = "127.0.0.1:8200";
            tls_disable = true; # TODO(§R4-3): TLS for the WAN join is an open decision — revisit before real use.
          };
          storage.raft = {
            path = "/var/lib/openbao";
            node_id = "vanguard";
            retry_join = [
              {
                leader_api_addr = cfg.retryJoinAddr;
              }
            ];
          };
          api_addr = "http://127.0.0.1:8200";
          cluster_addr = "http://127.0.0.1:8201";
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [8200 8201];
    };
  };
}
