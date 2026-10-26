# Argus bounded autonomy — behavior seed

**Status:** implemented in `feat/argus-ops-fix-20261026`
**Seed:** "lets check what type of action would be ok to give argus autonomous run power to fix" · "do open items"
**Owner:** desktop-nixos (plugin, runner, config), discovery host

## Destination

Argus may execute a small, config-owned set of idempotent host actions, with no
shell and no free-form target. Everything else stays recommend-only.

## In scope

- `status` on one allowlisted container (read-only).
- `restart_container` on one allowlisted container, gated by the alert-dedupe
  ledger saying the current episode is a repeat and by a runner-side 30-minute
  per-target rate limit.
- Audit line per executed action; tool errors reported, never raised.
- Allowlist v1: `prowlarr` on `discovery` only.

## Out of scope

Unit restarts, cross-host actions, Argo/Terraform/Vault writes, deletes,
backups, package upgrades, DB operations, shell access, and any parameter taken
from alert text. Those stay T2 (human) or T3 (never) per the one-pager.

## Control points

| Control | Where |
|---|---|
| Action enum | plugin schema (`ops_fix`) |
| Target allowlist | `/etc/ops-fix/allowlist.json` from Nix |
| Rate limit | runner state, 1800 s per target |
| Audit | `/var/lib/ops-fix/audit.jsonl` |
| No shell | argv lists only; `shell=True` absent |
| Fail closed | unknown action/target → `ok:false` |
