# NetBird overlay — implementation plan (build breakdown)

**Status:** Built (code complete, eval-verified, not deployed) — 2026-07-10

> **Build results (2026-07-10).** WP0–WP4 done by four sonnet agents + verified
> together: `just lint`/`fmt-check`/`structure-check` clean, and **zero
> netbird/pocket derivations** in `just dry` for laptop/discovery/voyager (true
> no-op, flags off). homelab-iac `tofu validate` passed on all four netbird modules
> + the Oracle edit (against the real fetched `netbirdio/netbird` 0.0.9 schema).
> **Correction folded back into the RFC §6:** the "ACL gates the control plane"
> claim was wrong — management API + signal are inherently fleet-wide; only the
> dashboard UI (`:8443`, admin-ACL) and PocketID are narrowed; the API's real
> protection is NetBird's JWT + peer-approval + PAT scope. Nothing deployed; Phase S
> + Phase O remain the human checklist below.

Build breakdown for [`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)
(RFC; all gates ruled §11). Maps every artifact to an owner + a verify gate.

## Guard rails (non-negotiable)

- **Everything opt-in, disabled by default.** New modules register under
  `flake.modules.*` and expose an `enable` flag defaulting `false`; host wiring
  imports them but leaves them off. **`just dry <host>` must stay a clean no-op**
  until a human flips the flag. Merging this build changes nothing live.
- **No secrets in git.** Modules *reference* sops keys (via existing
  `secrets/sops/secrets.yaml`); the keys themselves are created by a human op
  (Phase S). `.sops.yaml` gains cloud-host recipients (public keys only).
- **No remote/billing/deploy by agents.** Oracle `tofu apply` (reserved IP, SL),
  Cloudflare DNS, PocketID setup, secret creation, and host `switch` are
  **human-gated ops** (Phase S/O), out of agent scope.
- **New files `git add`ed before any `nix` eval** (dendritic: untracked = invisible).
- Verify = `just lint && just fmt-check` + `just dry <host>` (touched hosts) +
  `just structure-check`; IaC = `tofu validate` / `terragrunt hclfmt` (no apply).

## Work packages (→ agents)

**WP0 — Foundation (sequential, blocks the rest).** `modules/meta.nix`: add a
`netbird` fact (management URL, relay hostnames, overlay CIDR `10.100.0.0/16`) and a
`fleet.overlays` fact (`tailscale=100.64.0.0/10`, `netbird=10.100.0.0/16`); regen
`fleet.json` (`just fleet-json`). `.sops.yaml`: add `voyager` + `telstar`
(placeholder) age-recipient anchors (Q4) — public keys as TODO stubs the human
fills. Verify: `just lint`, eval `.#fleet`, `just structure-check`.

**WP1 — Client module.** `modules/networking/netbird-client.nix` →
`flake.modules.nixos.netbird-client`: wrap `services.netbird.clients.netbird`
(setup-key file, management URL from the `netbird` fact via a resolver-independent
address per RFC §4b, `services.resolved.enable`). `enable` flag default false; not
imported by any profile yet (opt-in per host). Verify: eval + `just dry laptop`.

**WP2 — Discovery control plane.** `modules/hosts/discovery/netbird-server.nix`:
oci-containers (Docker, Q1) for `management` (Postgres store, reuse `infra` PG,
Q5), `signal`, `dashboard`, `pocket-id`, `relay#1`; images **pinned to versioned
tags with a TODO to swap to Harbor-mirrored digests** (§8, human op); env from sops
(placeholder keys); `stuns:` = external (Q9); relays[] lists relay1+relay2 by
hostname. Gated behind an `enable` flag default false. SWAG proxy-conf + Tailscale
ACL note as TODO comments (Phase O). Verify: eval + `just dry discovery` clean
no-op with flag off.

**WP3 — Relay module (voyager + 2nd VM).** `modules/hosts/voyager/netbird-relay.nix`
as a reusable deferredModule: rootless-podman `netbirdio/relay`, publishes **:443
only** (WSS+QUIC), `NB_ENABLE_STUN` unset, built-in LE (Q3), metrics/health bound
to `tailscale0`, cgroup caps (§6b-H5), `NB_AUTH_SECRET` from host-specific-key sops
(Q4). Parameterized for reuse on the Track-1 2nd VM (adds `services.ddclient`
cloudflare, §4a). `enable` default false. Verify: eval + `just dry voyager` no-op.

**WP4 — homelab-iac.** New `netbird/` component (provider `netbirdio/netbird`
pinned in `.terraform.lock.hcl`): `groups`, `policies` (default-deny), `setup-keys`,
`posture-checks` units — scaffold + a committed default-deny policy export (§8).
`oracle/modules/instance`: reserved-IP resource + SL rules (443/tcp+udp, close 22,
2222 hardened) **written but not applied**. `cloudflare/dns`: `relay.<zone>` +
`relay2.<zone>` DNS-only records **written not applied**. `tailscale/acl`: add the
control-plane admin-only rule (§6). Verify: `terragrunt hclfmt`, `tofu validate`
(NO plan/apply — needs creds + is a live-network change).

## Human-gated ops (NOT agent work — checklist for you)

- **Phase S (secrets):** generate cloud-host age keys, add public keys to
  `.sops.yaml`, `sops` re-encrypt; mint `NB_AUTH_SECRET`
  (`openssl rand -base64 32`); create PocketID OIDC client secret + JWT signing key;
  store all in `secrets/sops/secrets.yaml` (via `rtk proxy sops`, per the
  truncation gotcha).
- **Phase O (ops):** `tofu apply` the Oracle reserved-IP + SL (verify billing);
  Cloudflare DNS apply; PocketID first-run + passkey enrol; mirror images into
  Harbor + swap tags→digests; SWAG proxy-conf deploy (servarr flow); Tailscale ACL
  apply; then per-host `just switch-<host>` following RFC §10 phase gates.

## Phasing

WP0 → (WP1 ∥ WP2 ∥ WP3 ∥ WP4) build+eval now. Phase S + Phase O are done by the
human, in RFC §10 order, after code review. Nothing here deploys.
