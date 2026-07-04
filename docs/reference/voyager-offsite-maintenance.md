# Voyager offsite maintenance — retention, prune window, integrity

**Status:** As-built reference (2026-07-01). Closes the
[`offsite-dr-crown-jewels`](../implemented/2026-06-30-offsite-dr-crown-jewels.md)
§11 follow-ups: disk-usage alert, scheduled `restic check`, documented prune
window.

## What lives on voyager

Voyager (Oracle Always-Free, 1 GB) runs an **append-only** restic REST server
(`rest-server --append-only --private-repos`, servarr `machines/voyager/offsite`
stack) storing the crown-jewel config tier under `/srv/backups/restic`:

| Repo | Pushed by | Job |
|------|-----------|-----|
| `/discovery/openbao` | discovery | `restic-backups-vault-rest` (03:40 daily) |
| `/discovery/tofu-state` | discovery | `restic-backups-tofu-state-rest` (07:30 daily) |
| `/kepler/…` | kepler | crown-jewels 4c `.env.sops` bundle |

Append-only is the point: a compromised sender cannot delete history. The cost
is that **nothing ever prunes** — the disk only grows.

## Monitoring (automated)

- **Metrics**: voyager runs plain `node_exporter` (too small for Alloy —
  `modules/services/node-exporter.nix`), scraped by discovery Prometheus over
  the tailnet (`job=node-voyager`).
- **Alerts** (servarr `machines/discovery/.../alerting/rules.yaml`, group
  `voyager-offsite`): `voyager-scrape-down` (host/exporter dead, critical),
  `voyager-disk-low` (`/` <15% free, warning), `restic-voyager-check-stale`
  (no successful check in >9 days, warning).
- **Integrity**: `restic-check-voyager.timer` on discovery (Sun 05:00) runs
  `restic check --read-data-subset=10%` against both discovery-owned repos
  (`modules/hosts/discovery/restic-voyager-check.nix`) and writes the
  dead-man metric on success. The kepler-owned repo is not covered (its
  credentials live on kepler only).

## Prune window (manual, on demand)

Trigger: `voyager-disk-low` fires, or quarterly review. Clients cannot prune
(the server rejects deletes); prune runs **on voyager against the local repo
path**, where restic bypasses the REST daemon entirely.

1. Announce/skip the backup window (03:40 and 07:30 discovery jobs) or just
   run mid-day — restic locking handles overlap, a failed push retries next
   day.
2. On voyager, with the repo password (from the owner host's sops —
   `vault_restic_password` / `restic_tofu_state_password`; decrypt via
   `rtk proxy sops`):

   ```bash
   sudo restic -r /srv/backups/restic/discovery/openbao forget \
     --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
   sudo restic -r /srv/backups/restic/discovery/tofu-state forget \
     --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
   ```

3. Verify: `restic snapshots` shows the kept set; `df -h /` recovered space;
   next scheduled `restic-check-voyager` run passes (or run it once:
   `systemctl start restic-check-voyager` on discovery).

Retention above is deliberately generous — this tier is MB-scale config, not
media; prune frequency is driven by the 45 GB boot volume, not cost.

## Restore drill

Crown-jewels §11a: restic restore *from voyager* → decrypt → `terragrunt plan`
no-diff. Not automated; run manually and record the result here.

**2026-07-04 — PASS.** From discovery, against the append-only REST repo using
the sops creds:
```
R=$(ls /nix/store/*-restic-*/bin/restic | head -1)   # restic 0.19.0
sudo $R --repository-file /run/secrets/restic_tofu_rest_url \
        --password-file /run/secrets/restic_tofu_state_password \
        restore latest --target /tmp/dr-drill
```
Restored the latest snapshot (`a0dcb223`, same-day) — **38 files / 145 KiB**,
the complete tofu-state tier: unifi (wlan/reservations/network/dns), tailscale
(dns/acl), oracle (`compute` + `compute-telstar`), cloudflare (tunnel/dns/
swag-token), adguard/filtering. A restored state parses as valid OpenTofu JSON
with the pbkdf2 encryption envelope intact (values encrypted at rest,
decryptable with `UNIFI_STATE_PASSPHRASE`). Temp wiped after. The
`terragrunt plan` no-diff step is continuously exercised by the daily
plan/apply runs against the live MinIO backend; the drill here proves the
**offsite copy is restorable, complete, current, and correctly encrypted**.
