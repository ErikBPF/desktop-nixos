# NetBird + PocketID declarative admin via Terraform (homelab-iac)

**Status:** Implemented (2026-07-12) — declarative admin applied end-to-end
(tokens minted → sops, PocketID client imported zero-diff, groups/policy/setup-key/
split-DNS applied, `Default` allow-all deleted → default-deny live, CIDR set to
`10.100/16`); **laptop enrolled as the first managed peer** (`10.100.141.14`,
`fleet-servers`). §8 rollout done. **Follow-ups (fixes + explorations) are open —
see §9.** Pivot spun out of
[`2026-07-11-pocketid-idp-for-netbird.md`](2026-07-11-pocketid-idp-for-netbird.md)
after the NetBird dashboard browser-SSO proved incompatible with PocketID
(deferred as an upstream bug). The control plane is **live and functional via
CLI**; this RFC makes the *administration* declarative so the broken dashboard
UI is never on the critical path.

> Scaffold for human judgment. The two provider facts are **verified** (both
> exist on the registry, versions/resources checked 2026-07-11). Decision gates
> (§6) and the bootstrap-token chicken-and-egg (§4) are the human calls. No
> agent runs `tofu apply` or mints tokens without a human in the loop (§7).

## 1. Why

The self-hosted NetBird overlay control plane (PocketID IdP + management/signal/
dashboard/relay#1 on `discovery`) is **up and proven**: `netbird up` enrolled the
first peer over the CLI's loopback PKCE flow; management/signal/relay connect;
account+peer exist. See the parent RFC's `**Status:**` for the deploy record.

**But the netbird *dashboard* browser-SSO is broken** — dashboard v2.90.3
(`@axa-fr/react-oidc`) only runs the OIDC code-exchange from a `#callback` URL
fragment, while PocketID (spec-compliant) returns the code in the query and
rejects a `#` in `redirect_uri`. Every local workaround failed (no query-mode
dashboard version to pin, no `response_mode=fragment` env, a SWAG `sub_filter`
`#callback` shim still yielded `code=undefined`). It needs an upstream netbird
fix. Meanwhile **everything the dashboard does is available declaratively**, so
we stop depending on it.

**Non-goals:** fixing the dashboard SSO (deferred, tracked upstream); the overlay
transition study; relay resilience (parent RFC). This RFC is *administration as
code* only.

## 2. Providers (verified 2026-07-11)

| System | Provider | Key resources | Auth |
|--------|----------|---------------|------|
| NetBird | **`netbirdio/netbird`** 0.0.9 (official) | `netbird_setup_key`, `netbird_policy`, `netbird_group`, `netbird_network`, `netbird_route`, `netbird_nameserver_group` (+ data sources) | NetBird **PAT** (`NETBIRD_MANAGEMENT_URL` + token) |
| PocketID | **`Trozz/pocketid`** (community) | `pocketid_client` (OIDC clients), users, groups | `POCKETID_BASE_URL` + `POCKETID_API_TOKEN` |

`homelab-iac` **already scaffolds a `netbird/` Terragrunt component** (provider
pinned `netbirdio/netbird` 0.0.9, default-deny policy) from the parent overlay
work — this RFC fills it in and adds a **`pocketid/`** peer component.

*Sources:* [registry: netbirdio/netbird](https://registry.terraform.io/providers/netbirdio/netbird/latest),
[github: Trozz/terraform-provider-pocketid](https://github.com/Trozz/terraform-provider-pocketid).

## 3. What becomes declarative

- **PocketID (`pocketid/` component):** the **NetBird OIDC client** (`pocketid_client`)
  — public + PKCE, exact callback/redirect URLs, scopes, logout URL. Ends the
  manual redirect-URL churn (the `/auth` vs `/` vs `/#callback` thrash was all
  hand-editing this in the UI). Optionally: admin groups for future group-based ACLs.
- **NetBird (`netbird/` component):** `setup_key`s (per host/role, `auto_groups`,
  `ephemeral`, `usage_limit`), `group`s, `policy`s (default-deny + explicit
  allows), `nameserver_group`s (split-DNS for `*.homelab`), `route`s if any. This
  is the full admin surface the dashboard would otherwise provide.

## 4. Bootstrap tokens (the chicken-and-egg — §-decision)

Both providers need an API token; the dashboard that would normally mint them is
the broken thing. Resolutions (both viable because the PocketID admin UI and the
netbird *API* both work):

- **PocketID token:** log into `id.<zone>` (passkey — **works**) → Settings → API
  Keys → create. Store in sops (`pocketid/api_token`). Human, one-time.
- **NetBird PAT:** mint via the management REST API using a user OIDC token
  (`POST /api/users/{id}/tokens`), obtainable from a `netbird` CLI login. Store in
  sops (`netbird/tf_pat`). Human, one-time. (Confirm the exact endpoint against
  mgmt 0.74.3 at wire-up.)

Secrets tier: these are **runtime IaC-provider creds** → per the SSOT map they
*could* live in Vault (iac-via-provider, D5), but bootstrap simplicity may favor
sops first. **Decision G3.**

## 5. CIDR fix (10.100/16) — folded in

Peer IPs currently come from netbird's random CGNAT pick (`100.110.0.0/16`,
overlaps Tailscale `100.64/10`); the parent RFC wanted a disjoint `10.100.0.0/16`.
Check whether the provider/API exposes the account peer-IP range
(`settings_network_range`); if so set it here (account is fresh — only throwaway
peers), else a `null_resource`/API call. Re-up peers after. **Decision G4.**

## 6. Decision gates (human)

| # | Gate | Options | Lean |
|---|------|---------|------|
| G1 | Repo placement | homelab-iac `netbird/`+`pocketid/` Terragrunt units | homelab-iac (it owns IaC + already has `netbird/`) |
| G2 | Import vs recreate | import the existing PocketID client + netbird account state, or recreate clean | import (avoid re-Issuing the working client-id) |
| G3 | Token secrets tier | sops now vs platform Vault | sops now, Vault later (least bootstrap friction) |
| G4 | CIDR range | keep `100.110/16` vs set `10.100/16` | set `10.100/16` while the account is fresh |
| G5 | Managed peers | which hosts run `netbird-client` (setup-key from TF) | start 1–2, expand |
| G6 | Dashboard SSO | keep deferred vs invest | deferred (upstream) |
| G7 | ACL model | default-deny + explicit `netbird_policy` allows | default-deny (matches the scaffolded component) |

## 7. Guard rails

- **`tofu apply` is human-run**, from a **wired LAN host** (homelab-iac convention;
  Wi-Fi apply can self-lock the network stack). Agents may write HCL + `tofu plan`.
- **Tokens via `rtk proxy sops`** only; verify key count; never bare `sops`.
- **Publish-and-pin (D9):** homelab-iac stays the owner of netbird policy/DNS;
  desktop-nixos owns the host OS + `fleet.netbird` facts. No live cross-repo reads.
- **Deploy discovery** (if module changes) only via `just deploy discovery …`
  (not deploy-rs — rolls back on flaky `home-manager-erik`).

## 8. Rollout (suggested)

1. Commit working desktop-nixos netbird config; revert the dead SWAG shim; tear
   down/keep the ad-hoc laptop daemon.
2. Mint PocketID API token + netbird PAT → sops (§4).
3. `pocketid/` component: import/manage the NetBird `pocketid_client` (§3).
4. Fill the `netbird/` component: setup-keys, groups, default-deny policy, DNS (§3).
5. Managed peers: TF setup-key → `netbird-client` module on host(s) (§6 G5).
6. CIDR → `10.100/16` (§5); re-up peers.
7. Dashboard SSO stays deferred; revisit on a netbird upstream fix.

## 9. Follow-ups — fixes + explorations

Surfaced by an adversarial party pass (Skeptic / Maintainer / Architect) after the
first managed peer landed, 2026-07-12. Items marked **(✓)** were verified live this
session; the rest are open. Fixes are confirmed problems; explorations need a probe
before a fix is designed.

### Fixes (confirmed)

- **F1 — Imperative state has no drift tripwire (✓).** `network_range =
  10.100.0.0/16` and the *deleted* `Default` allow-all policy live ONLY in the
  NetBird account state — the `netbirdio/netbird` 0.0.9 provider exposes no
  account-settings/policy-default resource, so both were set by a hand `curl PUT`/
  `DELETE`, not by TF. A DB restore from the vanguard PG replica or an account reset
  silently reverts the range to `100.110/16` **and resurrects the allow-all** →
  default-deny evaporates with zero plan diff. **Fix:** a `homelab-iac-drift`-style
  check (or `null_resource` + `local-exec` guard in `netbird/`) asserting
  `GET /api/accounts .settings.network_range == 10.100.0.0/16` AND `Default` policy
  absent; alert on mismatch. Owner: homelab-iac.

- **F2 — Peer approval OFF + a standing reusable setup-key (✓).** Verified
  `settings.peer_approval_enabled = false`; `fleet-server-bootstrap` is reusable
  (5 uses, expires 2026-07-18) and committed to `secrets.yaml`. A leaked key enrolls
  a rogue peer straight into `fleet-servers` — which `admin-ssh` can SSH into — with
  no approval gate. **Fix:** (a) enable peer approval via the mgmt API (the field
  exists on self-hosted despite the provider marking it Cloud-only — same
  imperative pattern as the CIDR); (b) decide the key lifecycle: one-off per
  enrolment (re-mint on `terragrunt apply`) vs standing + approval-gated. Owner:
  homelab-iac (API) + desktop-nixos (secret lifecycle). Note the 7-day expiry means
  any host enabled after 2026-07-18 fails to enrol until the key is re-minted +
  re-stored — no mechanism does this today.

- **F3 — `netbird-management` is a SPOF with no down-alert (✓ none found).** It was
  `failed` ~5h on 2026-07-12 before a human noticed; it is NOT in
  `modules.upgradeHealthCheck.criticalUnits` (so the 05:00 autoUpgrade crashed it
  without rollback) and no runtime container/unit-down alert covers it. The render
  guard (`ee669d8`) + `Restart=on-failure` (`035b3d9`) self-heal the *known* sops
  race, but a novel failure still fails silent-to-humans. **Fix:** add
  `docker-netbird-management.service` (+ `-config`, signal, relay, pocketid) to
  `upgradeHealthCheck.criticalUnits` (upgrade-time rollback) AND a runtime alert
  (Alloy/Prometheus unit-failed or an `/api` probe, reusing the dead-man's-switch
  pattern). Owner: desktop-nixos.

- **F4 — homelab-iac `feat/netbird-overlay` is unmerged.** All the declarative
  admin (pocketid client, groups, policies, split-DNS, setup-keys) is stranded on a
  branch; a `terragrunt apply` from `main` gets none of it. **Fix:** merge to main
  (squash). Owner: homelab-iac.

### Explorations (probe first)

- **E1 — Token rotation runway.** The netbird PAT + PocketID API key expire
  2027-07-12; on expiry every `terragrunt apply` fails auth with no reminder. Probe:
  a rotation runbook / calendar tripwire, or shorter-lived per-apply tokens.

- **E2 — Dual-overlay DNS for `*.homelab` (✓ no live conflict).** Both Tailscale
  MagicDNS and the new NetBird `homelab-split-dns` nameserver_group claim the zone;
  verified both resolve to `192.168.10.210` (same answer; `Nameservers 1/1` live on
  the laptop) — so no split-brain today, but two independent configs for one zone is
  a drift vector. Probe: which resolver systemd-resolved prefers on a dual-homed
  peer, and whether to skip the NetBird nameserver_group on hosts already on
  Tailscale (only NetBird-only peers strictly need it).

- **E3 — Off-LAN peer reachability unproven.** The mgmt floor is now discovery's LAN
  IP `192.168.10.210`, reachable off-LAN only via the advertised subnet route +
  `accept-routes`. Only an on-LAN peer (laptop) has enrolled. Probe: roam a genuinely
  off-LAN peer and confirm `netbird up` + relay traversal work through the LAN-IP
  floor.

- **E4 — sops recipients for future relay/DR peers.** `secrets.yaml` recipients =
  `&primary/&orion/&archinaut`; `&voyager/&telstar` are placeholders. Enabling
  `netbird-client` on voyager (relay) would fail to decrypt `netbird/setup_key`.
  Probe: mint real host age keys before enrolling those peers.

- **E5 — routes stay deferred** (already scaffolded empty, `netbird/routes/`): needs
  a LAN routing peer + an explicit expose-the-subnet decision before any route is
  filled (see `netbird/APPLY.md` §5).

---

*Cross-refs:* [`2026-07-11-pocketid-idp-for-netbird.md`](2026-07-11-pocketid-idp-for-netbird.md)
(IdP bring-up + the deferred dashboard-SSO blocker),
[`2026-07-10-netbird-selfhosted-overlay.md`](../proposals/2026-07-10-netbird-selfhosted-overlay.md)
(parent RFC — §8 IaC split, WP4),
[`2026-07-10-netbird-implementation-plan.md`](2026-07-10-netbird-implementation-plan.md).
Module: [`../../modules/hosts/discovery/netbird-server.nix`](../../modules/hosts/discovery/netbird-server.nix),
[`../../modules/networking/netbird-client.nix`](../../modules/networking/netbird-client.nix).
