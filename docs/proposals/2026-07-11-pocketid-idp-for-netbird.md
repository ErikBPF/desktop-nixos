# PocketID as NetBird's OIDC IdP — bring-up on discovery, idpOnly-first

**Status:** Implemented — full self-hosted NetBird control plane (PocketID IdP +
management/signal/dashboard/relay#1) LIVE on discovery behind SWAG
(`id`/`nb`/`nb-relay.homelab.pastelariadev.com`) 2026-07-11. Management runs on the
infra Postgres (dedicated `netbird` role) with PocketID OIDC (public + PKCE);
`nb/` → 200, `nb/api` → 401 (auth-gated). §5's env-var wiring was corrected to
`management.json` (`HttpConfig` + flow blocks) — the binary reads the file, not
`NETBIRD_AUTH_*` env; the relay HMAC + datastore key are rendered from sops at
activation (never baked). Remaining (human): dashboard passkey login + first
`netbird up` client enrolment (validates the gRPC routes + relay HMAC end-to-end).

> Scaffold for human judgment. PocketID env vars, the OIDC-client model, and the
> first-run/recovery flow are **researched and cited** (pocket-id.org,
> docs.netbird.io) — not guessed, per the plan-doc landmine #2. The order of
> operations is a **human-gated runbook**: no agent runs `switch-discovery` (§7).
> This RFC is the focused slice the NetBird implementation plan spun out
> ([`2026-07-10-netbird-implementation-plan.md`](2026-07-10-netbird-implementation-plan.md)
> §"Deploy status & discovered prerequisites"): stand PocketID up **without
> breaking the crown-jewel hub**, hand off the passkey + OIDC-client step, then
> wire NetBird management/dashboard to it.

## 1. Scope & non-goals

**In scope:** bring PocketID (the `netbird-pocketid` container in
[`../../modules/hosts/discovery/netbird-server.nix`](../../modules/hosts/discovery/netbird-server.nix))
up on **discovery**, served **tailnet-only** behind the existing SWAG wildcard at
`https://id.homelab.pastelariadev.com`, as NetBird's identity provider. Concretely:

- G-A — an **`idpOnly` mode** on `services.netbirdServer` that starts *only*
  PocketID and requires *only* PocketID's secret — clearing the sops-activation
  landmine (§3) so a first `switch-discovery` cannot fail the hub.
- G-B — the **PocketID env/secret model**, confirmed against current docs (§2).
- G-C — the **SWAG proxy-conf** for `id.<zone>` in the servarr repo (§4).
- G-D — the **NetBird↔PocketID OIDC wiring** (client model, redirect URLs, env
  matrix, issuer) so the follow-on full bring-up is unambiguous (§5).
- G-E — the **bootstrap order** with a verify gate per step (§6).

**Not in scope (unchanged from the parent RFC):** management/signal/dashboard/relay
resilience, voyager/vanguard relays, homelab-iac policy, the transition study.
Those are the parent RFC ([`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)).
This doc only makes the IdP real and correctly wired — the precondition for
everything else in Track B.

## 2. PocketID facts (researched, current release)

Confirmed against pocket-id.org's env-var reference and setup guide, and NetBird's
own PocketID integration doc. The module currently pins `pocketIdTag = "v2.10.0"`
(`ghcr.io/pocket-id/pocket-id`); re-verify these on the pinned tag before minting.

**Environment variables (exact names):**

| Var | Default | Use here |
|-----|---------|----------|
| `APP_URL` | `http://localhost:1411` | `https://id.homelab.pastelariadev.com` — sets issuer **and** WebAuthn RP-ID/origin (§ decision G3). |
| `ENCRYPTION_KEY` | *(unset)* | At-rest key encrypting PocketID's stored private keys (incl. the OIDC signing key). **≥16 bytes**, `openssl rand -base64 32`. Also accepts `ENCRYPTION_KEY_FILE`. **This is the one secret `idpOnly` needs.** |
| `DB_CONNECTION_STRING` | `data/pocket-id.db` (SQLite) | Leave unset → SQLite file under the `/app/data` volume (§ decision G2). Accepts a Postgres DSN if we ever move it. |
| `PORT` / `HOST` | `1411` / `0.0.0.0` | Backend listener; SWAG proxies to `netbird-pocketid:1411`. |
| `TRUST_PROXY` | `false` | **`true`** — behind SWAG; makes PocketID honour `X-Forwarded-*` (correct client IP + HTTPS scheme, needed for WebAuthn origin). |
| `PUID` / `PGID` | `1000` | File ownership on the `/app/data` bind mount. |

> **Env-var correction to fold into the module:** the module names the secret
> `netbird/pocketid_jwt_key` but its content is `ENCRYPTION_KEY=…`. The var name
> **`ENCRYPTION_KEY` is confirmed correct** (plan-doc landmine #2 cleared). The sops
> *key label* is misleading — it is not a JWT key, it is the at-rest encryption key.
> Since the secret **does not exist yet** (zero-migration rename), mint it as
> **`netbird/pocketid_encryption_key`** and update the module reference (§ decision
> G-A folds this in).

**First-run / admin bootstrap:** open web page — visit **`https://id.<zone>/setup`**,
create the initial admin, register the first **passkey** there. There is **no
mandatory setup code** for the first admin in the current release; the `/setup`
route is the bootstrap and self-closes once an admin exists. WebAuthn requires a
**secure context (HTTPS)** — satisfied by SWAG's valid wildcard cert (not by a raw
`localhost`/IP). ⇒ the SWAG proxy-conf (§4) must ship **before** first `/setup`.

**Recovery / passkey-less login (the §6a-Q6 "login code"):** admin-issued
one-time access token, either **Admin UI → Users → ⋯ → One-time link**, or CLI:

```
docker exec netbird-pocketid /app/pocket-id one-time-access-token <user-or-email>
```

prints a single-use, 1-hour link `http://localhost:1411/lc/<token>`. **Because we
serve tailnet-only, rewrite the host** — open `https://id.<zone>/lc/<token>`. This
is the deliberate out-of-band recovery kept enabled per the parent RFC §6a-Q6
(avoids the single-admin self-brick); treat issuance as a tier-0 admin action.

*Sources:* [pocket-id.org — env vars](https://pocket-id.org/docs/configuration/environment-variables),
[pocket-id.org — user management / one-time link](https://pocket-id.org/docs/setup/user-management),
[docs.netbird.io — PocketID (advanced)](https://docs.netbird.io/selfhosted/identity-providers/advanced/pocketid).

## 3. The sops-activation landmine (why `idpOnly` exists)

`netbird-server.nix` declares **four** sops secrets — `netbird/postgres_dsn`,
`netbird/auth_secret`, `netbird/oidc_client_secret`, `netbird/pocketid_jwt_key` —
all under `lib.mkIf cfg.enable`. Disabled, none evaluate, so `just dry discovery`
is a clean no-op today (verified in the plan doc). **The trap is at enable-time:**
`sops-nix` decrypts **every declared secret during activation**, and only
`netbird/auth_secret` currently exists in `secrets/sops/secrets.yaml`. Flip
`enable = true` as-is and discovery activation **fails** on the three missing
secrets — on the 24/7 crown-jewel hub.

We do **not** want to paper over it by minting placeholder values for the other
three, because (a) that would let `management`/`signal`/`dashboard`/`relay` start
before their real config exists (crash-loops on the hub), and (b) it violates the
bootstrap order — PocketID must exist **first** so the OIDC client can be created
in it **before** management is configured (§6). So the structural fix:

**`idpOnly` starts only PocketID and declares only PocketID's secret.** With
`idpOnly = true`, the module:

- declares **only** `sops.secrets."netbird/pocketid_encryption_key"` (§2 rename) —
  nothing else, so activation needs nothing but that one minted value;
- starts **only** the `netbird-pocketid` oci-container — not management/signal/
  dashboard/relay;
- ships nothing that references the not-yet-real Postgres/OIDC-client/HMAC secrets.

`idpOnly = false` (the "full" path) is the current behaviour — all containers, all
four secrets — reached only after §6 has captured the real values.

**Everything stays opt-in / disabled by default.** `services.netbirdServer.enable`
defaults `false`; `idpOnly` only matters once someone enables the module. **`just
dry discovery` must remain a clean no-op** until a human flips `enable` — that is
the eval gate (§6, step 0).

### 3a. Deploy mechanism — NixOS oci-container, **not** a servarr compose stack

discovery runs a **hybrid**: ~14 **servarr compose stacks** (SWAG, the `infra`
Postgres, monitoring, media, tools, ai-serving…) driven by the NixOS
`homelab.compose` module (`modules/hosts/discovery/compose.nix` +
`modules/server/orchestration.nix`) from `/home/erik/servarr/machines/discovery`
and recreated with `just kick-stack discovery <stack>`; **plus** two NixOS
`virtualisation.oci-containers` — `hermes` and this netbird control plane (incl.
PocketID). The netbird/PocketID containers are declared in Nix
([`../../modules/hosts/discovery/netbird-server.nix`](../../modules/hosts/discovery/netbird-server.nix),
`backend = "docker"`) and deployed by **`switch-discovery` (nixos-rebuild), not
`kick-stack`** — the parent RFC's Q1/Q2 ruling, mirroring the deliberate `hermes`
servarr→NixOS-oci cutover (`hermes-oci.nix` is the exact template netbird copies:
same `backend`, same `homelab-net`, same `/home/erik/homelab/apps/…` dataDir).

Rationale for the exception: the control plane is **substrate, not a household
workload** (desktop-nixos SSOT owns substrate), and its secrets are **sops**
(host/bootstrap tier, D5) delivered by sops-nix to `/run/secrets` — native to the
NixOS-oci pattern, not the servarr vault-agent / `.env.sops` flow. Only the
**ingress route** (SWAG proxy-conf, §4) and the **`infra` Postgres role** (§6)
are servarr-owned, because SWAG and Postgres are themselves servarr compose stacks.

> **Cross-mechanism dependency (verify at wire-up).** The netbird containers attach
> to the **`homelab-net`** bridge, which is **created by the servarr-pull oneshot**
> (`orchestration.nix`, `docker network create homelab-net`), i.e. by the
> servarr-compose layer — so that layer must have deployed on discovery for the
> bridge to exist (it always has; it drives the bulk of the host). Today the
> netbird/hermes oci units declare **no explicit `after`/`dependsOn`** on that
> oneshot and rely on docker unit start-retry. **Fix while wiring:** order the
> `docker-netbird-*.service` units `after` the network-create unit to remove the
> latent boot race.

## 4. SWAG proxy-conf (`id.<zone>`)

Today `id.<zone>` resolves to SWAG but has **no proxy-conf**, so it serves SWAG's
default page. PocketID is a NixOS oci-container on the `homelab-net` docker bridge;
SWAG (servarr `networking` stack) shares that bridge and reaches containers by name
— **exactly the `hermes-agent` pattern already in use** on discovery. Add one
proxy-conf, modelled on the existing `hermes.subdomain.conf`:

`references/repos/servarr/machines/discovery/config/swag/nginx/proxy-confs/pocket-id.subdomain.conf`:

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name id.*;
    include /config/nginx/ssl.conf;

    client_max_body_size 10M;

    location / {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        # NixOS oci-container on the homelab-net bridge (netbird-server.nix).
        set $upstream_app netbird-pocketid;
        set $upstream_port 1411;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }
}
```

- **WebAuthn correctness:** SWAG terminates the wildcard TLS (secure context), and
  `include /config/nginx/proxy.conf` forwards `X-Forwarded-Proto: https` +
  `X-Forwarded-Host`, which `TRUST_PROXY=true` makes PocketID trust → the WebAuthn
  **origin** it computes is `https://id.homelab.pastelariadev.com`, matching the
  RP-ID derived from `APP_URL`. Mismatch here is the classic passkey-registration
  failure, so this pairing (`TRUST_PROXY=true` ⇔ `X-Forwarded-*` from SWAG) is
  load-bearing, not cosmetic.
- **Delivery (servarr git-only flow):** edit under
  `references/repos/servarr/machines/discovery/` → `just prep-servarr` → commit +
  push in the servarr repo → `just pull-servarr discovery` → **`just kick-stack
  discovery networking`** to recreate SWAG so it loads the new proxy-conf. (SWAG
  reads proxy-confs at start; a reload/recreate is required — a `restart` is not
  enough for a *new* conf.)
- No new public surface: `id.<zone>` stays tailnet/LAN-only (parent RFC §5). The
  proxy-conf does not touch Cloudflare.

## 5. NetBird ↔ PocketID OIDC wiring (for the follow-on full bring-up)

Researched against **NetBird's own PocketID (advanced) doc** — the most specific
recipe. It **diverges from what the module currently assumes**, so this is where
the wire-up corrections live. Verify each against the pinned NetBird tag
(`netbirdTag = "0.74.3"`) at wire-up time; NetBird's auth env surface has moved
across releases.

**Client model — public + PKCE, no client secret (recommended, § decision G4).**
In PocketID → **Administration → OIDC Clients → Add**, create client **"NetBird"**:

- **Public Client: On**, **PKCE: On** → **no client secret is issued**.
- **Callback / redirect URLs:**
  - `https://nb.homelab.pastelariadev.com/auth`
  - `https://nb.homelab.pastelariadev.com/silent-auth`
  - `http://localhost:53000` (the CLI loopback for interactive `netbird up`)
- **Logout callback:** `https://nb.homelab.pastelariadev.com/`
- **Client Launch URL:** `https://nb.homelab.pastelariadev.com`
- Ensure a **`groups`** scope/claim is available (for group-based ACLs later).
- **Capture the generated Client-ID** — PocketID mints it; it is **not** the
  literal string `"netbird"` the module placeholders use. **Audience == Client-ID.**

**Management env (`netbird-management`), per the advanced doc — replaces the older
`NETBIRD_AUTH_AUTHORITY` style the module has now:**

```
NETBIRD_USE_AUTH0=false
NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT=https://id.homelab.pastelariadev.com/.well-known/openid-configuration
NETBIRD_AUTH_CLIENT_ID=<PocketID client-id>
NETBIRD_AUTH_AUDIENCE=<PocketID client-id>
NETBIRD_AUTH_SUPPORTED_SCOPES="openid profile email groups"
NETBIRD_AUTH_REDIRECT_URI=/auth
NETBIRD_AUTH_SILENT_REDIRECT_URI=/silent-auth
NETBIRD_TOKEN_SOURCE=idToken
NETBIRD_AUTH_DEVICE_AUTH_PROVIDER=none
```

**Issuer trailing-slash caveat (documented failure mode):** issuer =
`https://id.homelab.pastelariadev.com` — **no trailing slash** (NetBird's PocketID
doc calls this out specifically; a trailing slash breaks discovery). Sanity-check
by opening the `.well-known/openid-configuration` URL in a browser and confirming
it returns JSON.

**Device-authorization grant — disabled.** PocketID has limited device-flow
support; NetBird's PocketID recipe sets `NETBIRD_AUTH_DEVICE_AUTH_PROVIDER=none`
and the CLI relies on the interactive browser flow + `idToken`. **This is fine for
this fleet:** servers enrol via **setup keys** (parent RFC §6a — machines are not
user logins), and only human devices run interactive `netbird up`, which uses the
loopback (`localhost:53000`) browser flow, not device-code.

**Dashboard env (`netbird-dashboard`):** the SPA is the public/PKCE side of the
same client — `AUTH_CLIENT_ID` = the captured client-id, `AUTH_AUTHORITY` =
`https://id.<zone>` (no secret in browser-shipped code). Verify the exact dashboard
var names against the pinned `dashboardTag` — the dashboard image reads a slightly
different set than management.

**IdP-management API integration — deferred (§ decision G5).** NetBird can
optionally read users/groups from PocketID's management API
(`NETBIRD_MGMT_IDP=pocketid` + a PocketID **API token** as
`NETBIRD_IDP_MGMT_EXTRA_API_TOKEN` — an API token, **not** an OIDC client secret).
We **defer** it: group-based policy can read the **`groups` JWT claim** directly, so
first bring-up needs neither the extra token nor the coupling. Revisit if/when
group sync is wanted.

> **Net correction vs the current module:** it wires a **confidential**
> `NETBIRD_AUTH_CLIENT_SECRET` (from `netbird/oidc_client_secret`). The PocketID
> recipe is **public + PKCE (no secret)**. Under G4-recommended, the
> `netbird/oidc_client_secret` sops secret is **dropped**, and management gains the
> env block above. If the confidential path is chosen instead (G4-alt), keep the
> secret and add `NETBIRD_AUTH_CLIENT_SECRET`; either way, `NETBIRD_AUTH_CLIENT_ID`
> / `AUDIENCE` stop being the literal `"netbird"` and become the captured client-id.

## 6. Bootstrap order (human-gated runbook; verify gate per step)

Everything below is **human-run**. Agents may write/eval the code (steps 0–1) and
draft the proxy-conf (step 3), but **no agent runs `switch-discovery`, mints
secrets, or touches PocketID admin.** Secrets go through **`rtk proxy sops`** only
(the Bash hook truncates bare `sops` → data loss; back up + verify key count after
each write).

0. **Code — `idpOnly` refactor (agent-ok, eval-only).** Add
   `services.netbirdServer.idpOnly` (§ decision G1), gate the PocketID-only secret
   + container as in §3, rename the secret to `netbird/pocketid_encryption_key`.
   `git add` new files first. **Verify:** `just lint && just fmt-check &&
   just structure-check`; **`just dry discovery` is a clean no-op** (flag still off).

1. **Secret — mint PocketID's encryption key (human).**
   `ENCRYPTION_KEY=$(openssl rand -base64 32)` into `secrets/sops/secrets.yaml` as
   `netbird/pocketid_encryption_key`, via `rtk proxy sops`. **Verify:** key count
   before/after (+1), `git diff` shows only the sops block changed, file still has
   its `sops:` metadata (encrypted).

2. **SWAG proxy-conf (human, servarr flow).** Ship `pocket-id.subdomain.conf` (§4)
   → `prep-servarr` → commit/push (servarr) → `pull-servarr discovery` →
   `kick-stack discovery networking`. **Verify:** `curl -sSI
   https://id.<zone>/setup` from a tailnet host returns a PocketID page, **not**
   SWAG's default; TLS is the valid wildcard cert.

3. **Enable idpOnly + switch (human-gated switch).** Set
   `services.netbirdServer = { enable = true; idpOnly = true; }` on discovery →
   **human** `just dry discovery` (skim: only `docker-netbird-pocketid` +
   `sops-netbird-pocketid-encryption-key` appear; no management/signal/dashboard/
   relay units, no other secrets) → **human** `just switch-discovery`. **Verify:**
   `systemctl status docker-netbird-pocketid` active; `https://id.<zone>` loads
   over the tailnet; no other netbird unit exists.

4. **First admin + passkey (human, in PocketID).** Visit `https://id.<zone>/setup`,
   create the admin, **register the passkey immediately**, confirm `/setup` then
   closes (re-visiting redirects/404s). **Verify:** log in fresh with the passkey;
   issue one recovery `one-time-access-token` and confirm the rewritten
   `https://id.<zone>/lc/<token>` link logs in (recovery path proven **before** it
   is ever needed).

5. **Create the `NetBird` OIDC client (human, in PocketID).** Per §5 (public +
   PKCE, redirect URLs, launch/logout, `groups` scope). **Capture the Client-ID**
   (and, only under G4-alt, the client secret / a G5 API token) into
   `secrets/sops/secrets.yaml` via `rtk proxy sops`. **Verify:**
   `https://id.<zone>/.well-known/openid-configuration` returns JSON with the
   expected `issuer` (no trailing slash) and endpoints.

6. **Wire NetBird full (agent-ok code, human switch).** Apply the §5 corrections:
   real client-id in management + dashboard, public+PKCE env block, drop
   `oidc_client_secret` (G4), mint `netbird/auth_secret` (exists) +
   `netbird/postgres_dsn`, provision the `netbird` PG role/DB on the infra Postgres
   (**servarr** `infra` stack — `scripts/provision-db.sql`), ship the `nb.<zone>`
   proxy-conf (**servarr**, HTTP/2 + gRPC). Flip `idpOnly = false`.
   **Verify:** `just dry discovery`; **human** `just switch-discovery`; dashboard
   **passkey login** succeeds through PocketID; a manual `netbird up` test client
   registers. (This step is the parent RFC §10 phase 1 — tracked there.)

## 7. Guard rails & constraints (crown-jewel host)

- **Opt-in / disabled by default.** `enable = false` unchanged; `just dry
  discovery` stays a clean no-op until a human flips it (§6 step 0).
- **Human-gated switch.** No autonomous `switch-discovery`. Every `switch` in §6
  is human-run after a human reads the `just dry` diff.
- **Secrets via `rtk proxy sops` only** — the Bash hook truncates bare `sops -d`
  and re-encrypts a truncated file (data loss). Back up + verify key count each
  write. Cloud-VM host-key work (parent RFC §9/Q4) is **out of scope** here —
  PocketID lives only on discovery, decrypted by the existing recipients.
- **Eval-verified before deploy** — `just lint && just fmt-check &&
  just structure-check` + `just dry discovery` gate every code step. New files
  `git add`ed before any `nix` eval (untracked = invisible to the flake).
- **Conventional commits, no AI attribution.**

## 8. Decision gates

Ruled by a human before/at wire-up. Recommendation first where there is one.

| # | Gate | Options | Recommendation |
|---|------|---------|----------------|
| **G1** | idpOnly shape | (a) `idpOnly` **bool**; (b) a `mode` enum `idpOnly\|full`; (c) per-service `enable` flags | **(a) bool** — minimal code that clears the landmine; one axis, reads well, easy to drop when `full` is the norm. Per-service (c) is more surface than the two real states need. |
| **G2** | PocketID DB | (a) **SQLite** (default, file in the netbird dataDir); (b) infra Postgres | **(a) SQLite** — tiny, self-contained, single-file backup already inside discovery's btrfs-snapshot + restic path. Postgres is the thing **management** needs for DR/replication; PocketID gains nothing from it and adds coupling + a role to provision. |
| **G3** | WebAuthn RP-ID / origin (tailnet-only host) | derive from `APP_URL` | **RP-ID = `id.homelab.pastelariadev.com`, origin `https://id.homelab.pastelariadev.com`.** Stable across tailnet/LAN paths (same hostname + wildcard cert), so a passkey registered over the tailnet also validates over the LAN. Caveat: RP-ID is host-scoped — moving PocketID to another hostname invalidates existing passkeys; the login-code recovery (G6) covers that. |
| **G4** | NetBird OIDC client model | (a) **public + PKCE, no secret** (NetBird's PocketID doc); (b) confidential + client secret | **(a) public + PKCE** — matches NetBird's own PocketID recipe; removes the `netbird/oidc_client_secret` sops secret and a browser-side secret risk. (b) only if a later NetBird tag needs a confidential client — then re-add the secret. |
| **G5** | IdP-management API integration | (a) **defer** (JWT `groups` claim only); (b) enable now (`NETBIRD_MGMT_IDP=pocketid` + PocketID API token) | **(a) defer** — group ACLs read the `groups` claim; no extra token/coupling for first bring-up. Enable later only if user/group **sync** is wanted. |
| **G6** | MFA / login-code policy | ruled upstream (parent RFC §6a-Q6) | **Passkey-only primary; one-time login code kept enabled** as tier-0 recovery. Confirm applied in PocketID; prove the `/lc/<token>` path in §6 step 4 before relying on it. |
| **G7** | `/setup` exposure window | open until first admin exists | **Tailnet-only + register-admin-immediately.** `/setup` never faces the internet (SWAG tailnet/LAN-only); close the window by creating the admin the moment PocketID is up, and verify `/setup` then self-closes (§6 step 4). |

---

*Cross-refs:* [`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)
(parent RFC — §5 exposure, §6/§6a IdP+MFA, §9 secrets),
[`2026-07-10-netbird-implementation-plan.md`](2026-07-10-netbird-implementation-plan.md)
(discovered prerequisites this doc clears),
[`2026-07-10-vanguard-second-oracle-node.md`](2026-07-10-vanguard-second-oracle-node.md)
(sibling Track-1 node), [`../reference/service-exposure.md`](../reference/service-exposure.md)
(discovery exposure audit), module:
[`../../modules/hosts/discovery/netbird-server.nix`](../../modules/hosts/discovery/netbird-server.nix).
