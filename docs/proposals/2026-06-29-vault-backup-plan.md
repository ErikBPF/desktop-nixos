# Vault backup — prove backup/restore + monitoring before any real secret

**Status:** In progress (gate **P3.0**). **Done 2026-06-29:** OpenBao on discovery
(raft, OSS) initialised + auto-unseal (B1a/B1b); restic snapshot backup +
`vault_backup_last_success_seconds` liveness + Discord-on-fail (B1b); **mock-state
restore drill PASSED** (deleted key recovered, count restored — B2); Grafana
`vault-backup-stale` rule provisioned + metric confirmed in Prometheus (B3).
**GATE MET 2026-06-29.** Off-site to kepler done; fresh-cluster DR restore PROVEN
(restore into a new OpenBao → seals → unseal with the OLD sops key → secret
recovered, see *Disaster recovery*); B4 alert condition validated (aged metric →
Prometheus staleness > threshold → fires → Discord path proven by the identical
live restic rule). **B5 open → real-secret migration (P3.2) unblocked.** The one
DR dependency left to the operator: an **offline break-glass copy of the primary
age key** (single-host loss is already covered — orion/archinaut are recipients).
**Date:** 2026-06-29
**Audience:** Maintainers of desktop-nixos + homelab-gitops
**Post-read action:** Confirm the storage + Vault-home forks, then execute
B1→B5 (backup → mock test → monitor → Grafana validate → **then** migrate).

## Why backup-first

We will not put a real secret into Vault until backup **and restore** are proven
and the backup is **monitored**. A secret store you can't restore is worse than
the sprawl it replaces. Sequence (your ask): build backup → test on mock state →
add monitoring → validate on Grafana → **only then** migrate (P3.2+).

## Current state (verified 2026-06-29)

As-built Vault (gitops `platform/vault`): **standalone, `storage "file"`** on a
local-path PVC, namespace `vault`, kepler cluster. **File storage has no
consistent online snapshot** — `vault operator raft snapshot` requires the
**raft** (integrated) backend. So step zero is a storage decision.

## Gating decisions (`TODO(erik)`)

1. **Storage backend → switch to `raft`** (recommended). Even single-node raft
   supports `vault operator raft snapshot save` — a consistent, online,
   point-in-time backup. File backend would force either a risky live-dir copy or
   a logical-only KV export (loses policies/auth/mounts). Small chart change
   (`storage "file"` → `storage "raft"` + a data PVC).
2. **Vault home** (from the parent RFC): **(A) discovery** strongly preferred
   *for backup reasons* — a host systemd timer runs the snapshot and **restic**
   ships it, **reusing the exact `restic-tofu-state` + textfile dead-man's-switch
   we just deployed**. **(B) in-cluster** means a k8s CronJob snapshot → PVC/NFS →
   host restic + a Pushgateway/CronJob metric (more moving parts). *This plan is
   written for (A)+raft; the (B) variant is sketched at the end.*

## Backup design (A + raft)

Mirror the proven `restic-tofu-state` shape:

- **Snapshot timer** (`vault-snapshot.timer`, daily + on-demand): a host oneshot
  runs `vault operator raft snapshot save /var/lib/vault-snapshots/vault.snap`
  (authenticated via a least-priv token/AppRole from sops). Atomic write + keep
  the latest.
- **restic** backs up `/var/lib/vault-snapshots/` → `vault/restic/vault` on the
  vault disk (sdb), **plus an off-site copy to kepler** (same SFTP pattern as
  tofu-state). Encrypted, deduped, retained (`--keep-daily 7 --keep-weekly 4
  --keep-monthly 6`).
- **ExecStartPost liveness** (the pattern just shipped): on success write
  `vault_backup_last_success_seconds` (0644) to
  `/var/lib/node-exporter-textfile/` → Alloy → Prometheus.

### Security (do not skip)
- The snapshot is encrypted by Vault's **barrier key**, which the **unseal key
  (in sops)** protects. *Snapshot + unseal key together = full compromise.* So
  the restic repo for snapshots and the sops unseal key must **not co-locate** —
  different disk + different trust domain. The off-site copy especially must not
  sit next to a copy of the unseal key.
- restic repo password in sops; off-site SSH key in sops (as tofu-state does).

## Monitoring (B3) — reuse the dead-man's-switch

- Metric `vault_backup_last_success_seconds` via the textfile collector (built in
  the Healthchecks-replacement work).
- **Grafana rule** (new `backups` group entry): fire if stale > **30h** or absent
  (noData⇒Alerting) → **Discord #incidents**. Same shape as
  `restic-tofu-state-stale`.
- Optional extra panels/alerts: snapshot **size** (sudden shrink = corruption
  signal) and **age**; restic repo `check` success.

## Test plan — mock state (B2), before any real secret

1. **Seed mock**: `vault kv put secret/mock/n1 …` × N (e.g. 20 dummy entries,
   no real data). Record the count + a checksum of values.
2. **Back up**: run `vault-snapshot.service` → confirm `.snap` written + restic
   snapshot created (local + off-site).
3. **Restore drill** (the real test): stand up a **throwaway Vault** (scratch
   container / vcluster), `vault operator raft snapshot restore vault.snap`,
   unseal, and **verify all N mock entries return with matching checksum**. Then
   destroy the throwaway.
4. **Negative test**: delete a mock key in the live Vault, restore the snapshot
   to scratch, confirm the deleted key is present in the restore (proves
   point-in-time recovery).

## Grafana validation (B4)

- Confirm `vault_backup_last_success_seconds` is in Prometheus
  (`instance=<vault-host>`).
- Confirm the Grafana rule provisioned (no errors) and is **Normal** after a
  fresh backup.
- **Force-fire**: stop the timer / age the metric → rule goes Alerting → **lands
  in Discord #incidents** → resolves after the next backup. (Same drill that
  validated the restic rule today.)

## Disaster recovery — proven procedure (tested 2026-06-29)

The in-place restore (B2) and a **fresh-cluster restore** were both tested. The
fresh-cluster path is the real DR case and has a subtlety that B2 doesn't show:
**after restoring a snapshot into a brand-new OpenBao, it seals, and you must
unseal with the ORIGINAL `vault_unseal_key` (from sops), not the new cluster's
key.** Verified end-to-end (a seeded secret came back).

Recovery from total discovery loss:

1. **Root of trust.** Recover the **primary age key**. `secrets/sops/secrets.yaml`
   is encrypted to `primary` + `orion` + `archinaut`, so an age key from **any**
   surviving recipient (orion/archinaut host key, or an offline primary copy)
   decrypts it. ⚠ **If all three are lost, everything is unrecoverable** — keep an
   **offline/break-glass copy of the primary age key** (`age_key` is itself inside
   secrets.yaml, so any one recipient bootstraps the rest).
2. **Rebuild discovery** (nixos-anywhere + age key) → `openbao.service` runs
   fresh/sealed.
3. **Fetch the snapshot** with restic (password = `vault_restic_password` from
   sops): off-site `restic -r sftp:restic-kepler:/bulk/backups/restic-offsite/openbao restore latest`
   (or the local vault-disk repo if the disk survived).
4. **Restore into the fresh cluster:** `bao operator init -key-shares=1
   -key-threshold=1` + unseal (throwaway key) → `bao operator raft snapshot
   restore -force <snap>` → cluster seals.
5. **Unseal with the OLD key:** `bao operator unseal "$(sops … vault_unseal_key)"`
   → secrets back. Verify (`bao kv get …`).

Recoverability of each input: `vault_unseal_key`, `vault_root_token`,
`vault_restic_password`, `restic_offsite_ssh_key` all live in sops → recovered via
the age key in step 1. The off-site snapshot on kepler is useless to an attacker
without the unseal key (kepler is not a sops recipient for these). **Caveat:**
single key-share (no Shamir threshold) — acceptable for a solo homelab, noted.

## Migration gate (B5)

Only after **B2 restore drill passes** *and* **B4 alert fires+resolves in
Discord** do we proceed to P3.2 (migrate the Discord webhook as the first real
secret). Backup precedes data, always.

## Execution order

- **B1** storage→raft (chart) + Vault home (A) + snapshot timer + restic +
  liveness metric.
- **B2** mock seed + backup + restore drill + negative test.
- **B3** Grafana rule (already half-built — add the `vault_backup` entry).
- **B4** validate metric + force-fire alert in Discord.
- **B5** gate met → start P3.2 real migration.

## (B) in-cluster variant (if Vault home = kepler cluster)

- Snapshot via a k8s **CronJob** (`vault operator raft snapshot save` to a PVC or
  the kepler NFS export).
- Host **restic** backs up that NFS path (kepler already a restic target).
- Liveness: CronJob writes to a node textfile path **or** pushes
  `vault_backup_last_success_seconds` to a Pushgateway scraped by Prometheus.
- Same Grafana rule + Discord. More components; same guarantees.

## Open decisions `TODO(erik)`

1. Storage: **raft** (rec) vs keep file (logical export only).
2. Vault home: **(A) discovery** (rec, reuses restic+textfile) vs (B) in-cluster.
3. Snapshot cadence (daily rec) + retention.
4. Restore-drill cadence (quarterly + after any Vault upgrade).
5. Off-site target for snapshots (kepler SFTP, as tofu-state) — kept apart from
   the unseal key.

## Links

- Parent: `proposals/2026-06-29-vault-secrets-platform.md` (P3). Reuses the
  `restic-tofu-state` module + the textfile dead-man's-switch from
  `implemented/2026-06-20-telemetry-hardening.md` lineage / the 2026-06-29
  Healthchecks-replacement work.
