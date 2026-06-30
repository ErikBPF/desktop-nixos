# OpenBao root-token recovery (discovery)

**Status:** ✅ Executed 2026-06-30 — recovery successful. New root minted from the
unseal key, sops resealed (`vault_root_token` + `vault_snapshot_token` +
`vault_agent_secret_id`), the kindle-dash robot secret sealed into
`secret/home/harbor`, the snapshot backup confirmed working again, and the
`generate-root` endpoint re-disabled (405). Kept as the as-built record + the
prevention rule below.

## Problem

The valid OpenBao root token's value is lost (2026-06-30). The 2026-06-29
rotation (Claude session `0c3260d1`) minted an orphan root-policy token via
`bao token create -orphan -policy=root -ttl=0 -field=token`, printed only its
length, stashed it root-only to `/run/openbao-newroot` "for the caller to fetch +
drop", and **dropped it** — but the new value was **never written to sops** (sops
kept the old token, which was then revoked). Exhaustively confirmed unrecoverable:

- sops `vault_root_token` — **working copy AND `HEAD`** (commit `c58be86`) → `403`.
- sops `vault_snapshot_token` → `403` (revoked too).
- literal **not in any of 66 session transcripts** (minted to a var, used by ref).
- `/run/openbao-newroot` removed (discovery hasn't rebooted, so not a tmpfs loss).
- vault-agent approle login fails (stale `secret_id`) and is read-only anyway.

**Impact:** reads/services unaffected (vault-agent's live token + approle reads
still render every secret). But **no new writes/admin** — this blocks the
remaining P3.3 secret migrations and the kindle-dash robot-secret seal, and the
nightly raft-snapshot backup (`restic-backups-vault`, uses `vault_snapshot_token`)
has been **failing since the rotation** (check `vault_backup_last_success_seconds`
/ Grafana `vault-backup-stale`).

## Why `generate-root` returns 405

Not a bug. OpenBao **≥ 2.5.0 disables the `sys/generate-root/*` endpoints by
default** (an unauthenticated-cancellation security concern); they're re-enabled
per-listener with `disable_unauthed_generate_root_endpoints = false`
([release notes](https://openbao.org/community/release-notes/2-5-0/),
[api-docs](https://openbao.org/api-docs/system/generate-root/)). Deprecated as of
2.5.3 in favour of `auth/token/create` from a sudo token — but we have **no valid
token**, so `generate-root` with the unseal key is the only path. Seal is
**shamir, t=1/n=1**, and the one unseal key is in sops → it needs only that key.

## Recovery (non-destructive — no re-init, no data loss)

Each step verified before the next. The raft snapshots (local + kepler off-site)
are the backstop; nothing here touches storage.

1. **Open the endpoint, briefly.** In `modules/hosts/discovery/vault.nix` add to
   `listener.default` (loopback) only:
   ```nix
   disable_unauthed_generate_root_endpoints = false;
   ```
   `just dry discovery` → `just switch-discovery`. **Gotcha:** `restartIfChanged
   = false` on openbao → a switch won't reload the listener; manually
   `systemctl restart openbao && systemctl restart openbao-unseal` (re-unseals).
   **Verify:** `BAO_ADDR=http://127.0.0.1:8200 bao operator generate-root -status`
   returns 200 (not 405). *Security:* the endpoint is loopback-only (the tailnet
   listener is left untouched, and is firewalled + default-deny ACL except
   kepler). Keep the window to minutes.

2. **Mint a new root token** with the unseal key (sops → `/run/secrets/vault_unseal_key`,
   root-read), entirely on discovery, value never printed:
   ```sh
   bao operator generate-root -cancel 2>/dev/null || true
   INIT=$(bao operator generate-root -init -format=json)   # nonce + otp
   bao operator generate-root -nonce="$NONCE" -format=json "$UNSEAL"  # encoded token
   bao operator generate-root -decode="$ENC" -otp="$OTP"   # new root token
   ```
   **Verify:** `VAULT_TOKEN=<new> bao token lookup` shows `policies=[root]`.

3. **Persist before anything depends on it** (the lesson from the incident —
   never leave the only copy ephemeral):
   - `rtk proxy sops set secrets/sops/secrets.yaml '["vault_root_token"]' "\"<new>\""`
     (RTK truncates raw `sops`; use `rtk proxy`). **Verify:** decrypt → 23 keys
     intact + the new token `lookup`s OK.
   - Re-mint the snapshot token (fixes the broken backup): with the new root,
     `bao token create -policy=snapshot -period=768h -field=token` → `sops set
     '["vault_snapshot_token"]'`.
   - Re-mint the vault-agent approle secret-id if needed (manual approle login
     failed): `bao write -f auth/approle/role/vault-agent/secret-id` → `sops set
     '["vault_agent_secret_id"]'` (vault-agent's live token keeps it running
     meanwhile; only matters on its next re-auth).

4. **Drain the deferred writes** (the original trigger):
   - kindle-dash robot: `bao kv patch -mount=secret home/harbor
     HARBOR_ROBOT_USER=… HARBOR_ROBOT_SECRET=…` from `/home/erik/harbor-mirror-robot.env`,
     then `rm` that 600-file. Update `harbor-mirror.sh` / the harbor RFC to source
     the robot cred from Vault. **Verify:** `bao kv get secret/home/harbor` → 4 keys.
   - Any other pending P3.3 secret moves.

5. **Re-disable the endpoint.** Remove the `disable_unauthed_…=false` line, `just
   switch-discovery`, restart openbao + openbao-unseal. **Verify:** `generate-root
   -status` → 405 again (closed).

6. **End-to-end verify:** new root `lookup` OK; `systemctl start
   restic-backups-vault` → success + `vault_backup_last_success_seconds` fresh;
   vault-agent still renders; robot secret present.

## Rollback / safety

- Every step is reversible and storage-safe (generate-root mints a token; it does
  not write the secret store). If the listener switch misbehaves, openbao is
  loopback+tailnet-only — revert the module + restart.
- If a sops `set` ever looks truncated (RTK history), restore the file from git or
  a pre-edit copy and retry via `rtk proxy sops`. Snapshot a fresh backup once the
  snapshot token is restored.

## Prevention

- Leave `generate-root` endpoints disabled (default) after recovery.
- Rotation runbook: mint new → **write to sops + commit + `lookup`-verify** →
  *then* revoke old. Never revoke-before-persist; never leave the only copy in
  `/run`.
- Consider a second unseal-key holder / a break-glass root token stored in the
  password manager so a lost token isn't a single point of failure.
