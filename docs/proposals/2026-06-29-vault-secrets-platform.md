# Secrets platform — Vault as runtime SSOT, sops as root-of-trust

**Status:** Proposal (sub-RFC — implements **P3** of
`2026-06-29-repo-ssot-srp.md`; judgment marked `TODO(erik)`)
**Date:** 2026-06-29
**Audience:** Maintainers of desktop-nixos + servarr + homelab-gitops + homelab-iac
**Post-read action:** Resolve the `TODO(erik)` forks (Vault home, unseal, auth
methods, path layout, migration cadence), then execute phases P3.1–P3.5.

## Execution status (resume here — 2026-06-29)

**Done + deployed + verified:**
- **P3.0** — OpenBao (OSS, raft) live on discovery, auto-unseal, dual restic
  backup (local vault-disk + off-site kepler), liveness metric + Grafana
  `vault-backup-stale` alert. **DR proven** (fresh-cluster restore → unseal with
  the OLD sops key; runbook `reference/vault-disaster-recovery.md`).
- **P3.2** — Discord webhook **fully de-duped**: in OpenBao `secret/shared/discord`;
  host services via **vault-agent** files; grafana/scrutiny via vault-agent
  `env_file`; removed from **both** sops stores. AppRole `vault-agent` (policy
  `discord-read`) + creds in sops (`vault_agent_role_id/secret_id`).
- **P3.1b** — lab ESO **repointed to discovery OpenBao** (2026-06-29). Tailnet
  listener `100.76.140.121:8200` beside loopback (firewalled to `tailscale0`, no
  TLS — WireGuard transport); ACL `kepler → discovery:8200`; OpenBao `eso` AppRole
  (policy reads `secret/data/{lab,shared}/*`). gitops `ClusterSecretStore`
  renamed `vault-incluster → vault-discovery` (raw tailnet IP), demo at
  `secret/lab/demo`. **In-cluster vault chart + Argo app deleted.** **Verified
  e2e:** ESO re-synced `demo-secret` from discovery over the tailnet. NOTE:
  `generate-root` is unsupported on this OpenBao build — the **root token was
  rotated** (orphan root-policy token) after an operator-session leak.

**sops bootstrap secrets** (desktop-nixos `secrets.yaml`): `vault_unseal_key`,
`vault_root_token` (rotated 2026-06-29), `vault_snapshot_token`,
`vault_restic_password`, `vault_agent_role_id`, `vault_agent_secret_id`. OpenBao
on `127.0.0.1:8200` (host) + `100.76.140.121:8200` (tailnet, lab ESO).

**In progress:**
- **P3.3** — servarr `.env.sops` → Vault. **7 stacks migrated + verified
  2026-06-29** (`.env.sops` 119→97 keys): tunneling, monitoring, media-server,
  tools, media, ai-serving, networking + a **shared-db render** (POSTGRES/REDIS
  consumed by infra/ai-serving/media-server). Mechanism: vault-agent renders
  `secret/home/<name>` → `/run/vault-agent/<name>.env`; `orchestration.nix`
  `vaultEnvStacks` (now an **attrset** stack→[basenames]) layers each as an extra
  `--env-file` (Vault wins over the sops `.env`); compose keeps its `${VAR}`
  interpolation. Cutovers verified non-disruptively via `compose config` (0 unset
  warnings) — running containers keep identical values, no recreate.
  **Deferred:** cross-host `LITELLM_MASTER_KEY`/`MINIO_ROOT_USER` (need a kepler
  vault-agent), shared `*ARR_API_KEY` + `GRAFANA_ADMIN_PASSWORD` (need homepage
  coordination), infra-local vault/vaultwarden/minio-tfstate creds (critical +
  circular), and **harbor** (special-cased: prepare-generated, 2 real secrets,
  dead 7-var `harbor.yml`). **OPERATIONAL: run all `sops` via `rtk proxy sops` —
  the RTK hook truncates `sops -d` and corrupted `.env.sops` once (recovered via
  git); see memory `rtk-sops-truncation`.**

**Next (not started):**
- **P3.4** — iac provider tokens → Vault.
- Operator action for DR: **offline break-glass copy of the primary age key**
  (a git-ignored `BREAK-GLASS-age-key.md` generator exists; copy off-fleet).

## Context

Per the SSOT/SRP plan (D5): **one platform Vault = runtime-secret SSOT** (docker
via vault-agent, k8s via ESO, iac via the Vault provider); **sops = root-of-trust
+ host/build/bootstrap only**. Today secrets sprawl across **four** stores and a
secret created this week (the Discord webhook) already lives in **two** of them.
This RFC designs the consolidation and the migration off the sprawl.

## Current state (as-built, verified 2026-06-29)

- **sops — desktop-nixos** `secrets/sops/secrets.yaml` (~17 keys): host keys,
  wifi PSK, restic password, tailscale keys, **discord_webhook_incidents/deploys**, …
- **sops — servarr** `machines/discovery/.env.sops` (**125 vars**): every
  compose stack's runtime config + **DISCORD_WEBHOOK_*** + SCRUTINY_DISCORD_URL.
- **homelab-iac** `.env` / `.env.sops`: Cloudflare/UniFi/Tailscale + MinIO state creds.
- **Vault — already scaffolded in homelab-gitops**: `platform/vault/` (Helm
  chart + values), `clusters/kepler/apps/vault.yaml` (Argo app),
  `platform/external-secrets/` + `clustersecretstore-vault.yaml` (ESO → Vault),
  a demo `externalsecret.yaml`, and a SWAG `vault.subdomain.conf` ingress.
  **⚠ As-built places Vault *inside the kepler lab cluster*.**

**The conflict to resolve:** D5 says the platform Vault is **always-on and
independent of the disposable lab** (D2/D3 — lab is self-contained + torn down via
vcluster). A Vault that lives *in* the lab cluster dies or risks loss every time the lab
is rebuilt, and makes **home depend on the lab** — backwards. So the scaffolded
in-cluster Vault must be **repositioned**.

## Decision: where Vault lives (`TODO(erik)` — recommend A)

- **(A) Vault on discovery** (the 24/7 home host), as a platform-labelled
  service — *not* "home", *not* in the lab cluster. Lab ESO and home vault-agent
  both reach it over the network; tearing down the lab never touches secrets.
  Honors "lab disposable" best. The gitops `platform/vault` chart is repurposed:
  keep ESO + a `ClusterSecretStore` pointing at the **external** discovery Vault;
  drop the in-cluster Vault server.
- (B) Keep Vault in the kepler **base** cluster, and contract that the base
  cluster (not the vclusters) is always-on platform. Less moving — but home now
  depends on the kepler cluster for secret refresh, and "rebuild the lab" gets
  delicate.

*Recommend A.* It matches D5 as written and the disposability model.

## The boundary rule (sops ↔ Vault) — concrete

**sops** (in `desktop-nixos`, host-age-key-decryptable, available at
boot/activation) — the minimal bootstrap/root-of-trust set:
- host SSH / age keys; secrets baked into NixOS units at activation (wifi PSK,
  restic password); **Vault unseal key + root token**; **vault-agent AppRole
  bootstrap creds**; the iac **bootstrap** token.

**Vault** (runtime, fetched by a running consumer) — everything else:
- app creds, DB passwords, API keys, **Discord webhooks**, litellm keys, the
  non-bootstrap Cloudflare/UniFi/Tailscale tokens, etc.

Test: *"needed before Vault is reachable, or by Nix at build/activation?"* →
sops. Else → Vault.

## Consumers & auth methods (`TODO(erik)` on specifics)

| Consumer | Path | Auth to Vault |
|----------|------|---------------|
| **lab k8s** (gitops workloads) | ESO `ClusterSecretStore` → ExternalSecret | **k8s auth** (ServiceAccount JWT) — no static creds |
| **home docker** (servarr, discovery) | **vault-agent** renders `.env` / secret files | **AppRole** (role-id/secret-id; secret-id bootstrapped via sops) |
| **host systemd** (nixos, cross-boundary secrets) | vault-agent writes secret files for units | AppRole (shared with docker agent or per-host) |
| **homelab-iac** | Vault **provider** (or `vault read` at plan) | token / AppRole (occasional) |

KV layout (`TODO(erik)`): kv-v2 mount with a path convention, e.g.
`home/<stack>/…`, `lab/<app>/…`, `shared/…` (Discord webhooks), `iac/<provider>/…`.

## Unseal (`TODO(erik)`)

Homelab-pragmatic: **manual/auto-unseal with the unseal key in sops**, applied by
a boot-time oneshot (semi-auto), vs transit/cloud-KMS auto-unseal (more infra).
Recommend sops-stored unseal key + an unseal unit — keeps the root of trust in
the one bootstrap store, no cloud dependency.

## Atomicity & bootstrap fit

- **Build/activation = sops only** (D9): `nixos-rebuild` works with Vault down.
- **Runtime fetch from Vault = the one sanctioned runtime dependency.** Mitigate
  home's exposure: vault-agent **caches** the last render, so a Vault blip leaves
  the last-good `.env` in place; only a *new* secret needs Vault live.
- Slots into the DR order (SSOT/SRP §Bootstrap): sops age key → network → hosts →
  **Vault (unseal via sops)** → Argo/obs → workloads.

## Migration phases

- **P3.0 — Backup-first gate.** Before any real secret enters Vault, prove
  backup **and restore** + monitor it. See
  `proposals/2026-06-29-vault-backup-plan.md` (raft snapshot → restic → textfile
  dead-man's-switch → Grafana/Discord; mock-state restore drill). P3.2 is blocked
  until this passes.
- **P3.1 — Stand up / reposition Vault (decision A).** Deploy Vault on discovery
  (or contract the base cluster, per the fork); automate unseal; put unseal key +
  root token + vault-agent AppRole in sops. Point lab ESO `ClusterSecretStore` at
  it. *Verify:* `vault status` sealed→unsealed on boot; ESO syncs the demo secret.
- **P3.2 — Proof migration: the Discord webhook.** ✅ **Host side done 2026-06-29:**
  webhook in OpenBao `secret/shared/discord`; **vault-agent** on discovery (AppRole,
  read-only `discord-read`) renders it to `/run/vault-agent/discord_webhook_incidents`;
  `swag-cert-monitor` / `restic-tofu-state` / `homelab-iac-drift` /
  `vault-backup-onfail` cut over; **`discord_webhook_{incidents,deploys}` deleted
  from desktop-nixos sops** (verified: alert POST via the Vault-sourced value lands
  in #incidents). **Container side also done 2026-06-29:** vault-agent renders
  `/run/vault-agent/discord.env`; grafana + scrutiny `env_file` it;
  `DISCORD_*`/`SCRUTINY_DISCORD_URL` **removed from servarr `.env.sops`** (litellm
  crons were vestigial — no live timer). **Webhook fully de-duped — single-sourced
  from OpenBao `secret/shared/discord`.**

- **P3.1b — Repoint lab ESO to the discovery OpenBao (decision A).** ✅ **DONE
  2026-06-29 — verified e2e** (ESO re-synced the demo secret from discovery over
  the tailnet; in-cluster vault chart + Argo app removed). 4
  touchpoints:* (a) **desktop-nixos** — OpenBao listener on discovery's tailnet IP
  (`100.76.140.121:8200`) beside loopback + firewall to `tailscale0`; consider TLS
  (tailscale already encrypts transport). (b) **homelab-iac** — tailnet ACL
  `kepler → discovery:8200` (currently default-deny). (c) **OpenBao** — an `eso`
  AppRole (policy reading `secret/data/lab/*` + `shared`). (d) **homelab-gitops** —
  `ClusterSecretStore vault-incluster` (`http://vault.vault.svc:8200`) →
  `http://discovery:8200` with the new roleId/secret_id; then **delete
  `platform/vault` + `clusters/kepler/apps/vault.yaml`**. Verify ESO re-syncs.
  Blast radius = lab only (disposable).
- **P3.3 — servarr `.env.sops` → Vault.** ✅ *Pattern + first stack (tunneling)
  done 2026-06-29.* Per-stack: vault-agent renders `secret/home/<stack>` to
  `/run/vault-agent/<stack>.env`; `orchestration.nix` `vaultEnvStacks` layers it
  as a second `--env-file` (Vault wins). Only **real secrets** move (~55/119);
  config stays in sops `.env`. *Verify:* recreated stack reads identical values
  (compare via `docker inspect`, **not** `docker exec printenv | pipe` — that
  truncates long values over ssh). harbor deferred (special-cased). ~120 remain.
- **P3.4 — iac tokens → Vault** (composes with the cloudflare-token RFC).
- **P3.5 — Shrink sops** to the bootstrap set; document the final boundary.

## Risks

- **Home ← Vault runtime dependency.** Mitigated by vault-agent caching + keeping
  any *home-critical-at-boot* secret in sops. A new household secret needs Vault
  up; existing renders survive an outage.
- **Single Vault = blast radius.** Mitigate: backup Vault storage (restic, like
  tofu-state), and the unseal key lives offline/break-glass in sops.
- **125-var migration is large** — phase per stack, never big-bang; keep the
  encrypted `.env.sops` as rollback until each stack is proven on Vault.

## Open decisions `TODO(erik)`

1. Vault home: **(A) discovery** vs (B) kepler base cluster.
2. Unseal: sops-key + boot unit vs KMS auto-unseal.
3. Auth: AppRole vs token for docker/host vault-agent; per-host vs shared role.
4. KV path convention (`home/`, `lab/`, `shared/`, `iac/`).
5. Migration cadence for the 125 servarr vars (which stacks first).

## Links

- Parent: `proposals/2026-06-29-repo-ssot-srp.md` (P3). Composes with
  `proposals/2026-06-28-cloudflare-token-terraform-migration.md` (iac tokens) and
  `proposals/2026-06-20-cluster-homelab-gitops.md` (the gitops/ESO scaffold).
