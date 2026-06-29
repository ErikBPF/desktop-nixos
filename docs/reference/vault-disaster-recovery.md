# OpenBao — disaster recovery runbook

**Status:** Reference (as-built; procedure **tested 2026-06-29**)
**Scope:** Recover the platform secrets store (OpenBao on discovery) from loss —
a single sealed/corrupt node, a rebuilt host, or total destruction.

OpenBao is the runtime-secret SSOT (`modules/hosts/discovery/vault.nix`); losing
it without recovery loses every runtime secret. This runbook is the proven path.

## Prerequisite — the one thing DR depends on

**An offline break-glass copy of the primary age key** (`age127vmpu9…`). It is the
root of trust: it decrypts `secrets/sops/secrets.yaml`, which holds
`vault_unseal_key`, `vault_root_token`, `vault_restic_password`, and the off-site
ssh key. `secrets.yaml` is encrypted to **primary + orion + archinaut**, so a
single host loss is survivable (any survivor's key decrypts it; the primary
`age_key` is itself inside `secrets.yaml`). **If discovery + orion + archinaut are
all lost and no offline primary copy exists → unrecoverable.** Keep a copy
off-fleet (password manager / paper / hardware token).

## Inventory (where everything lives)

| Item | Location |
|------|----------|
| OpenBao data (raft) | discovery `/var/lib/openbao` |
| Snapshot (local) | restic repo `/home/erik/vault/restic/openbao` (vault disk, sdb) |
| Snapshot (off-site) | restic `sftp:restic-kepler:/bulk/backups/restic-offsite/openbao` |
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

## Notes

- Single key-share (no Shamir threshold) — solo-operator choice; the unseal key's
  protection is sops + the age key.
- The off-site snapshot on kepler is unreadable without the unseal key (kepler is
  not a sops recipient for these secrets).
- Design: `docs/proposals/2026-06-29-vault-secrets-platform.md`,
  `…-vault-backup-plan.md`. Memory: `openbao-platform-vault`.
