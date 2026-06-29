---
title: Migrate Cloudflare API tokens to Terraform-managed (homelab-iac)
status: In progress — Phase 1+2 DONE (2026-06-29): bootstrap perms added to the iac token, swag-dns01 minted + bridged to SWAG, temp token revoked. Phase 3 (tunnel) + 4 (sweep) open.
date: 2026-06-28
audience: Maintainers of desktop-nixos + homelab-iac
post-read-action: Decide the bootstrap-credential shape + per-token scope, then execute the phases.
---

# Migrate Cloudflare API tokens to Terraform-managed

## 1. Why

Cloudflare API tokens are currently **hand-made in the dashboard** and pasted
into sops files. That drift just caused a real outage: SWAG's DNS-01 token
expired/invalid → no `*.homelab.pastelariadev.com` cert → every discovery
subdomain down (grafana/harbor/kindle all `000`). Hand-made tokens have no
single source of truth, no rotation story, and no audit. Goal: **every
*consumer* API token is a `cloudflare_api_token` resource in `homelab-iac`** —
least-scope, named, rotatable (`taint`/recreate), revocable (`destroy`).

First step already scaffolded: `cloudflare/swag-token/` + `modules/api-token/`
(provider v4 `cloudflare_api_token`, Zone:DNS:Edit on `pastelariadev.com`).

## 2. Inventory (today — all manual)

| Token | Scope | Consumer | Where stored | Class |
|-------|-------|----------|--------------|-------|
| `CLOUDFLARE_API_TOKEN` (iac) | Zone:DNS:Edit + Account:Tunnel:Edit (dual) | iac provider — `cloudflare_record` + tunnel cfg | iac `.env.sops` | user API token |
| `CLOUDFLARE_API_TOKEN` (SWAG) | Zone:DNS:Edit | certbot DNS-01 → `cloudflare.ini` | servarr `.env.sops` | user API token |
| `CLOUDFLARE_TUNNEL_TOKEN` | per-tunnel connector | cloudflared | servarr `.env.sops` | **tunnel connector secret** (not a user API token) |

desktop-nixos itself holds no CF token. The tunnel connector secret is a
different object (issued by the tunnel, not `/user/tokens`) — it can be made
declarative via the tunnel resource, but it's a secondary target.

## 3. The irreducible bootstrap (the honest limit)

"Remove all tokens not generated via Terraform" is achievable for every
*consumer* token, but **one credential must stay manual**: the one the provider
authenticates with to *create* tokens. Creating a `cloudflare_api_token`
requires the caller to hold **User → API Tokens → Edit**, and that creating
credential cannot itself be Terraform-created by a lesser token (chicken-egg).

So the end state is **one manual bootstrap/management token**, not zero:

- **Bootstrap token** (manual, iac `.env.sops`, provider auth) — perms:
  `API Tokens:Edit` (to manage tokens) **＋** the perms iac *applies directly*:
  `Zone:DNS:Edit` (for `cloudflare_record`) ＋ `Account:Cloudflare Tunnel:Edit`
  (tunnel config). This **replaces** today's dual-scope token and adds token
  management. It is the single root of the declarative chain.
- Everything else becomes a Terraform `cloudflare_api_token` resource.

`TODO(erik)`: bootstrap = a dedicated **scoped bootstrap token** (preferred —
revocable, auditable) **vs** the account **Global API Key** (works but
all-powerful, not revocable without rotating everything). Recommend the scoped
bootstrap token.

## 4. Target state

```
homelab-iac (provider auth = bootstrap token, manual, iac .env.sops)
├── cloudflare/dns/         cloudflare_record …            (bootstrap's DNS:Edit)
├── cloudflare/tunnel/      cloudflare_zero_trust_tunnel…  (bootstrap's Tunnel:Edit)
├── cloudflare/swag-token/  cloudflare_api_token swag-dns01  → SWAG  (scaffolded)
└── cloudflare/<svc>-token/ cloudflare_api_token …          → future per-service
```

Each consumer token: least-scope, `output token_value` (sensitive, in encrypted
state), bridged to its consumer's secret store.

## 5. The bridge (state → consumer) — the unglamorous part

A minted token lives in iac's encrypted TF state; the consumer reads a *file*,
not state. So each token needs a one-time hand-off, e.g. for SWAG:

```
cd cloudflare/swag-token && terragrunt output -raw token_value
→ servarr .env.sops: the SWAG cloudflare token var (swag-init writes it into
  /config/dns-conf/cloudflare.ini as dns_cloudflare_api_token)
→ just push-env discovery
→ recreate swag letting swag-init run (RUNBOOK; never --no-deps)
```

This is **declarative ownership, not zero plumbing**. `TODO(erik)`: accept the
manual `output → sops` step, or script a `just sync-cf-token <unit> <consumer>`
helper. Recommend the helper once there's >1 token.

## 6. Migration phases

1. ✅ **Bootstrap (done)** — the iac `CLOUDFLARE_API_TOKEN` gained User-scoped
   `API Tokens: Read+Write`, so it can now mint tokens.
2. ✅ **SWAG token (done)** — `cloudflare/swag-token/` applied (swag-dns01
   minted, `id=fbe210de…`), value bridged to servarr `.env.sops` (§5), SWAG
   serving on it; temp token revoked. Migration's core goal met for SWAG.
3. **Tunnel** (optional) — bring the connector secret under the tunnel resource;
   output → servarr; revoke the hand-made tunnel token.
4. **Sweep** — list dashboard tokens (`GET /user/tokens`), revoke every one not
   represented by a Terraform resource (only the bootstrap remains manual).
5. **Doc + memory** — record the bootstrap token as the one manual exception;
   update `swag_cert_cloudflare_flow` memory (token now Terraform-owned).

## 7. Risks / decisions

- **Bootstrap token power** — it can mint tokens. Mitigation: scoped (not Global
  Key), in iac `.env.sops` only, on the wired-LAN apply host. Accept as the root.
- **Token value in state** — already mitigated (repo state is pbkdf2/aes-gcm
  encrypted; `UNIFI_STATE_PASSPHRASE`).
- **Outage coupling** — SWAG cert depends on a token now in iac state; a botched
  rotation could break certs. Mitigation: SWAG keeps the last good cert; the
  registries-style upstream fallback doesn't apply to certs, so **rotate in a
  window** and verify `/dash.png` + a subdomain after.
- **`cloudflare_api_token` value is create-only** — rotation = `terraform taint`
  + re-bridge, not an in-place edit. Document it.
- `TODO(erik)`: provider is `~> 4.0`; the v5 provider reworks token resources —
  decide whether to pin v4 for this or bump (separate change).

## 8. Recommendation

Do **Phase 1–2 now** (bootstrap + swag-dns01) — it both starts the migration and
**fixes the live SWAG outage** with a Terraform-owned least-scope token, instead
of re-pasting another hand-made one. Phases 3–4 (tunnel, sweep) follow once the
pattern + bridge helper are proven. The one honest caveat: a single scoped
bootstrap token stays manual by Cloudflare's design — "all tokens declarative"
means *all consumer tokens*, plus one auditable root.
