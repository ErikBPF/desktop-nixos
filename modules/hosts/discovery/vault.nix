# Platform secrets store — OpenBao (OSS, MPL drop-in for HashiCorp Vault) on
# discovery, the always-on home host. Positioned as a *platform* service (D5 of
# the SSOT/SRP plan): runtime-secret SSOT for home docker (vault-agent), lab k8s
# (ESO), and iac (provider). sops stays the root-of-trust/bootstrap. Lives on
# discovery (not the disposable lab cluster) so tearing down the lab never
# touches secrets. See docs/proposals/2026-06-29-vault-secrets-platform.md (P3)
# and -vault-backup-plan.md (P3.0 — backup/restore must pass before real secrets).
#
# OpenBao over Vault: nixpkgs `vault` is BUSL/unfree; OpenBao is API-compatible
# (`bao` CLI, raft snapshots, ESO `vault` provider all work).
#
# B1a (this module): stand up the sealed, raft-backed server. It holds NOTHING
# until `bao operator init` + unseal (a deliberate, irreversible step that mints
# the unseal keys → sops). Backup/monitoring (B1b) is added after init, once the
# snapshot token exists. The module's StateDirectory=openbao (0700) owns
# /var/lib/openbao; restartIfChanged=false so a rebuild doesn't reseal it.
_: {
  flake.modules.nixos.discovery-vault = _: {
    services.openbao = {
      enable = true;
      settings = {
        ui = true;
        # Loopback only, no TLS on the local listener for now. Network reach for
        # lab ESO / remote vault-agent is added deliberately (Tailscale or SWAG,
        # with TLS) after the server is initialised and backed up.
        listener.default = {
          type = "tcp";
          address = "127.0.0.1:8200";
          tls_disable = true;
        };
        # Raft (integrated) storage → consistent online snapshots
        # (`bao operator raft snapshot save`), the backbone of the P3.0 backup plan.
        storage.raft = {
          path = "/var/lib/openbao";
          node_id = "discovery";
        };
        api_addr = "http://127.0.0.1:8200";
        cluster_addr = "http://127.0.0.1:8201";
      };
    };
  };
}
