# OpenBao — disaster recovery runbook

**Status:** Reference (procedure tested 2026-06-29; automated isolated drill added 2026-07-24; custody evidence reviewed 2026-09-07, human gates pending)
**Scope:** Recover the platform secrets store (OpenBao on discovery) from loss —
a single sealed/corrupt node, a rebuilt host, or total destruction.

OpenBao is the runtime-secret SSOT (`modules/hosts/discovery/vault.nix`); losing
it without recovery loses every runtime secret. This runbook is the proven path.

## Prerequisite — the one thing DR depends on

**An independently recoverable primary age key.** It decrypts the SOPS
bootstrap material needed for OpenBao recovery. The existing
[passphrase-age escrow](../../secrets/escrow/README.md) provides the private
encrypted-copy path through the password manager and Voyager; its passphrase
requires a password-manager copy plus an offline copy outside the home. Never publish the
encrypted escrow in Git or store its passphrase on the ciphertext host.

A recipient name does not establish which hosts hold its private key. Surviving
fleet copies can help with host loss, but do not prove recovery after losing the
home or primary operator. The [custody record below](#recovery-custody-acceptance)
separates shipped tooling from that human evidence.

## Recovery custody acceptance

**2026-09-07: B4/S1 remain pending operator evidence.** This is the single
acceptance record for physical escrow and second-custodian accessibility.
Record role aliases, dates, and outcomes only: no personal names, addresses,
password-manager item IDs, secret values, or key-derived evidence.

| Gate | Required witness | Role alias / witness date / result |
|---|---|---|
| B4 — offline custody | Confirm the escrow passphrase has an offline copy outside the home, independently accessible if the password manager is unavailable. | Pending / not witnessed / pending |
| S1 — second custodian | Confirm an agreed recovery role other than the primary operator; witness access to the private encrypted age-key blob, offline passphrase, encrypted bootstrap material, and instructions without home services, runtime Vault, or the primary operator. | Pending / not witnessed / pending |
| Recovery accessibility | On a controlled recovery machine, witness that the independently retrieved age key decrypts the required bootstrap material without displaying its contents. Record pass/fail and dependencies, not outputs. | Pending / not witnessed / pending |

The operator supplies missing role/date/outcome evidence; placeholders are not
completion. Close B4 only with its physical witness; close S1 only with its role
and independent recovery-access witness. If a dependency fails, keep the affected
gate pending and record the value-free blocker. Recheck after custody or key
changes and during the existing quarterly recovery review.

Use the existing [escrow mechanics](../../secrets/escrow/README.md) and
[break-glass guide](../guides/break-glass.md). `just escrow-age-key-verify`
compares a local blob with the live key; it cannot prove independent retrieval
or second-custodian access. Successful backups and isolated OpenBao restore
drills also cannot close custody gates. This handoff grants no authorization to
copy or rotate keys, mint another root token, change policies, or restore over
production. Any required secret operation needs its own exact authorization.

Safe local checks on 2026-09-07 observed `secrets/escrow/age-key.age` present,
gitignored, and untracked, and the primary age-key file present. The local
`ssh-key.age` was absent; this does not establish whether a private remote copy
exists. No secret contents were read, no remote escrow copy was checked, and no
physical or independent-retrieval witness was supplied.

Delivery review: `/pl` retained the shipped escrow and rejected a new service;
`/ip` selected one documentation slice with manual acceptance and link checks.
Independent plan review required distinguishing Kepler's same-home mirror from
outside-home custody and local comparison from cold retrieval. The
[behavior contract](../behaviors/recovery-custody/recovery-custody.feature) is
manual and unautomated; it is not a passing recovery test. Rollback is limited
to reverting these documentation edits; no runtime state changes. Final
independent review passed after the custody wording corrections; both repository
documentation checks passed. Physical acceptance remains pending.

## Inventory (where everything lives)

| Item | Location |
|------|----------|
| OpenBao data (raft) | discovery `/var/lib/openbao` |
| Snapshot (local) | restic repo `/home/erik/vault/restic/openbao` (vault disk, sdb) |
| Snapshot (other host, same home) | restic `sftp:restic-kepler:/bulk/backups/restic-offsite/openbao`; host-loss mirror, not outside-home protection |
| Snapshot (outside home) | Voyager append-only REST (`restic-backups-vault-rest`) and B2 (`restic-backups-vault-b2`); credential-bearing repository locations remain in SOPS |
| Unseal key / root token / restic pw | sops `secrets/sops/secrets.yaml` |
| Backup liveness alert | Grafana `vault-backup-stale` → Discord #incidents |

## Scenario A — node sealed (reboot / restart)

`openbao-unseal.service` auto-unseals on boot from the sops key. If it didn't:
```bash
ssh -p 2222 erik@192.168.10.210
export BAO_ADDR=http://127.0.0.1:8200
bao operator unseal "$(sudo cat /run/secrets/vault_unseal_key)"
bao status      # Sealed=false
```

## Scenario B — data corrupt / lost, host intact

Restore the latest snapshot into the running node, then unseal with the original
key (a restore reseals the node):
```bash
# fetch latest snapshot (off-site shown; use the local repo if the disk is fine)
export RESTIC_PASSWORD="$(sudo cat /run/secrets/vault_restic_password)"
restic -r sftp:restic-kepler:/bulk/backups/restic-offsite/openbao restore latest --target /tmp/restore
export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$(sudo cat /run/secrets/vault_root_token)"
bao operator raft snapshot restore -force /tmp/restore/var/lib/vault-snapshots/openbao.snap
bao operator unseal "$(sudo cat /run/secrets/vault_unseal_key)"   # node sealed after restore
bao status && bao kv get secret/<known-path>                       # verify
rm -rf /tmp/restore
```

## Scenario C — total loss (rebuild discovery from zero)

Proven fresh-cluster path (the key subtlety: a restored fresh node **seals** and
unseals with the **original** key, not the new one):

1. **Root of trust** — restore the primary age key (break-glass) to the
   workstation / new discovery (`~/.config/sops/age/keys.txt`).
2. **Rebuild discovery** — `just nixos-anywhere …` / install + age key →
   `openbao.service` runs fresh, sealed, empty.
3. **Fetch the snapshot** (off-site):
   ```bash
   export RESTIC_PASSWORD="$(sops -d secrets/sops/secrets.yaml | sed -nE 's/^vault_restic_password: "?([^"]+)"?$/\1/p')"
   restic -r sftp:restic-kepler:/bulk/backups/restic-offsite/openbao restore latest --target /tmp/r
   ```
4. **Init the fresh node** (throwaway key) so there's an unsealed target, then
   restore the old snapshot:
   ```bash
   export BAO_ADDR=http://127.0.0.1:8200
   bao operator init -key-shares=1 -key-threshold=1 -format=json   # new throwaway key
   bao operator unseal "<new-key>"
   bao operator raft snapshot restore -force /tmp/r/var/lib/vault-snapshots/openbao.snap
   ```
5. **Unseal with the OLD key** (from sops — the restore brought back the old
   barrier):
   ```bash
   bao operator unseal "$(sops -d secrets/sops/secrets.yaml | sed -nE 's/^vault_unseal_key: "?([^"]+)"?$/\1/p')"
   bao status      # Sealed=false → all secrets recovered
   ```

## Verify after any recovery

- `bao status` → `Initialized=true Sealed=false`.
- `bao kv get secret/<known>` returns expected data.
- Consumers re-sync (ESO in lab, vault-agent on home/host) once Bao is unsealed.
- A fresh backup runs clean (`systemctl start restic-backups-vault`) and the
  Grafana `vault-backup-stale` alert returns to Normal.

## Quarterly isolated drill

`openbao-restore-drill.timer` runs on the first day of January, April, July,
and October. It restores the latest snapshot into a temporary raft node bound
only to `127.0.0.1:18200`, unseals it with the production key, authenticates
through the production AppRole, and proves a known path exists without printing
its value. Production `:8200` and `/var/lib/openbao` are untouched.

Run it manually through the documented entry point:

```bash
just openbao-restore-drill
```

Success updates
`/var/lib/node-exporter-textfile/openbao_restore_drill.prom`. Re-run after every
OpenBao upgrade.

## Notes

- Single key-share (no Shamir threshold) — solo-operator choice; the unseal key's
  protection is sops + the age key.
- A snapshot needs the corresponding unseal material for recovery. Do not infer
  host separation from SOPS recipient names; verify key distribution separately.
- Design: `docs/implemented/2026-06-29-vault-secrets-platform.md`,
  `…-vault-backup-plan.md`. Memory: `openbao-platform-vault`.
