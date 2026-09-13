# Key rotation

**Status:** Reference; key-distribution and retirement procedure source-reviewed 2026-09-13.

When (and when not) to rotate the fleet's keys and secrets, and how. Rotation is
a risk trade-off, **not** hygiene theater: every rotation is itself a chance to
brick something (the OpenBao root-token brick — `implemented/2026-06-30-openbao-root-recovery.md`
— happened *during* a rotation that never wrote the new token back to sops). So
**rotate on triggers, not on a blind calendar**, and weight effort by blast
radius.

Related: `implemented/2026-06-30-offsite-dr-crown-jewels.md` (the DR anchor these
keys protect), `disaster-recovery.md` in `homelab-iac` (state DR),
`reference/vault-disaster-recovery.md` (OpenBao DR).

## Always rotate immediately (event-driven)

- **Laptop lost / stolen** → the sops **age key** and everything it decrypts. It
  holds the root of trust in plaintext (`~/.config/sops/age/keys.txt`).
- **A secret committed in plaintext / pasted into a chat / leaked in logs** →
  that secret.
- **Password-manager breach** → the **escrow passphrase** (and anything else
  stored there).
- **A person with access leaves** → shared secrets they saw.
- **Host decommissioned or its host key lost** → drop it as a sops recipient
  (that *is* an age-recipient rotation — see below).

## Per-key policy

| Key | Rotate when | Cost | Policy |
|-----|-------------|------|--------|
| **sops age key** (root of trust) | Compromise, laptop loss, recipient host retired | High | **Never on a calendar.** Trigger-only. Largest blast radius. |
| **escrow passphrase** (seals `keys.age`) | Possible exposure (typed on a shared box, PW-mgr breach) | Low | Trigger-only; cheap, so don't hesitate. |
| **discovery→voyager REST password** | Exposure, or ~annual | Low | Annual OK. Low blast radius — grants only *append* to voyager; cannot *read* backups (needs the restic repo password). |
| **restic repo passwords** (`restic_tofu_state_password`, `vault_restic_password`) | Compromise only | High | Trigger-only. Old snapshots stay under the old key. |
| **`UNIFI_STATE_PASSPHRASE`** (tf-state encryption) | Compromise | Medium | Trigger-only. |
| **`restic_offsite_ssh_key`** (SFTP → kepler) | Compromise, or ~annual | Low | Annual OK. |
| **OpenBao root token** | After every admin use | Built-in | Already the pattern — keep it. |
| **OpenBao unseal key** | Operator change / compromise | High (rekey) | Trigger-only; brick risk is real. |
| **Tailscale auth keys** | Node re-enrol | Low | As needed. |

## How to rotate each

All sops edits go through `rtk proxy sops` (the RTK Bash hook truncates plain
`sops -d`, which re-encrypts a truncated file — see `memory/rtk_sops_truncation.md`);
verify the key count before/after every edit.

### sops age key (root of trust)

The heaviest, most brick-prone rotation in the fleet — it re-encrypts every
sops file **and** must get the new private key onto every host, or sops-nix
can't decrypt and the fleet bricks on next activation/reboot. Do the **two-phase**
below; **never** the naive "re-encrypt then redeploy" — see the trap.

**Key model (source checked 2026-09-13).** System SOPS reads
`/var/lib/sops-nix/key.txt`; Home Manager reads
`~/.config/sops/age/keys.txt` ([module](../../modules/services/sops.nix)). These
are independent files. Inventory the current recipient rules, encrypted files,
and key holders before rotating; a historical host list is not a distribution
checklist. Preserve unrelated host identities and recipients throughout.

> **TRAP — updating the user key does not update an existing system key.**
> [First-boot activation](../../modules/services/first-boot.nix) installs a
> nonempty staging file into the system key store, replacing its contents. It
> copies staging into the user store only when that file is absent. Without
> staging, it copies the user key to the system store only when the system store
> is empty or absent. Consequently, `just rsync-sops` updates only the user
> store; activation alone does not synchronize both existing stores. Never
> stage a new-only key during the additive phase: it would replace the system
> store's still-needed identities.

**Phase A — additive (old key remains usable):**
1. Generate the replacement in an operator-controlled `0700` temporary
   directory with `umask 077`; keep the private key file `0600`. Record its
   public recipient with `age-keygen -y`, never its private value in logs.
2. **Add** the new recipient wherever the old recipient is used, keeping the
   old and unrelated recipients. Start with `.sops.yaml` in `desktop-nixos`,
   `homelab-iac`, and `servarr`; inventory other consumers rather than assuming
   those three exhaust the key's authority.
3. Run `rtk proxy sops updatekeys <file>` for every affected encrypted file.
   Verify recipient coverage and unchanged secret-name counts. Publish the
   additive recipient changes through the owning repositories.
4. **Distribute to both stores** on every affected host and the workstation.
   Add the new identity to each existing store without removing any existing
   identity. Keep `/var/lib/sops-nix/key.txt` owned by `root:root`, mode `0600`,
   and the Home Manager store owned by its user, mode `0600`. Use a controlled
   private transfer; do not put key values in arguments or terminal output.
   For staging-based activation, supply the complete additive system key set
   and update an existing Home Manager store separately. Do not assume the two
   stores contain identical unrelated identities.
5. **Prove the replacement from each installed store.** Extract only the
   identity matching the new public recipient into a private temporary file,
   separately from the installed system and Home Manager files. In an isolated
   verification environment, make that file the only available decryption
   identity: exclude default age files, SSH identities, key commands, and other
   SOPS provider credentials or metadata access. Decrypt every affected
   encrypted file needed by that store with plaintext directed to `/dev/null`.
   Require success; record only host, store, encrypted-file path, recipient and
   exit status. As a control, repeat with no identity and require failure; a
   successful control means a fallback provider is still available. Delete the
   temporary identity files after verification. Never remove keys from live
   stores to perform this test.
6. **Verify service health separately.** Use the documented host activation
   entry point in an accepted window, confirm system and Home Manager secret
   consumers recover, and inspect failures without printing secret values.
   Successful activation with old and new keys is not proof that the new key
   works. Do not enter Phase B until both the isolated decrypt proof and health
   checks pass for every affected store and host.

**Phase B — retire the old recipient from current ciphertext:**
7. **Remove** only the old recipient from the affected rules and run
   `rtk proxy sops updatekeys <file>` for every affected file, then
   `rtk proxy sops rotate --in-place <file>` to replace its data encryption key.
   Complete both operations before publishing; `updatekeys` alone retains the
   data key that a removed identity may already know. Recheck the
   new-identity-only decrypt gate and unchanged plaintext before publishing.
   Keep unrelated recipients. This ordering follows the [SOPS key-management
   procedure](https://getsops.io/docs/usage/key-management/#rotating-secrets-after-a-key-in-a-key-group-has-been-compromised).
8. Redeploy through each owner's documented entry point and confirm both
   system and Home Manager consumers remain healthy.
9. Remove the old identity from both stores on every affected host only after
   convergence. Clean temporary key material using the storage-appropriate
   procedure; filesystem snapshots and old ciphertext may still retain it.
   Recipient removal does not revoke the old key's ability to decrypt copies
   of historical ciphertext. Rotate exposed secret values separately when the
   trigger was compromise.
10. **Re-escrow:** `! just escrow-age-key` (fresh strong passphrase) →
    `just escrow-age-key-push` → `just escrow-secrets`; verify with
    `! just escrow-age-key-verify`.

**Ordering / safety notes.**
- Workstation activation can disrupt a GUI session. Use an accepted window or
  the documented boot-generation path followed by a planned reboot.
- Auto-upgrades can consume a Phase-B publication before a manual deployment.
  Complete distribution and new-identity-only verification everywhere before
  publishing removal of the old recipient.
- Hosts using independent identities keep those recipients. Whether a host
  also holds the primary key must come from the current inventory.

### escrow passphrase
`! just escrow-age-key` (choose a new passphrase) → `just escrow-age-key-push`.
Update the passphrase in the password manager + the one offline copy.

### discovery→voyager REST password
One value in two places (they must match — the URL basic-auth and voyager's
htpasswd):
1. servarr `machines/voyager/.env.sops` → `RESTIC_TOFU_PASSWORD` (dotenv;
   `rtk proxy sops set --input-type dotenv --output-type dotenv …`).
2. desktop-nixos `secrets/sops/secrets.yaml` → the password inside
   `restic_tofu_rest_url` **and** `restic_vault_rest_url`.
3. Commit/push servarr → `just pull-servarr voyager` → `just kick-stack voyager
   offsite` (init rebuilds htpasswd). Commit/push desktop-nixos → `just
   switch-discovery`.
4. Verify: `sudo systemctl start restic-backups-tofu-state-rest` on discovery →
   snapshot lands (a mismatch shows as **401**, see gotcha below).

### restic repo passwords
Use restic's multi-key support, not a wholesale re-encrypt:
`restic -r <repo> key add`, deploy the new `passwordFile`, then
`restic -r <repo> key remove <old-id>`. Do it per repo (local + kepler + voyager
copies share the password, so rotate the sops secret once and redeploy).

### restic_offsite_ssh_key (SFTP → kepler)
New ed25519 keypair → private into `secrets/sops/secrets.yaml`
(`restic_offsite_ssh_key`), public into kepler's
`services.resticOffsiteTarget.authorizedKey`. Redeploy discovery then kepler.

### OpenBao root / unseal
Follow `reference/vault-disaster-recovery.md` and the root-recovery runbook.
Root token: after minting, **write it to sops immediately** — the brick was
caused by skipping that step.

## Gotcha

restic REST with `--private-repos` returns **401 Unauthorized** (not 403) when
the URL path does not start with the authenticated username. After any REST
credential change, confirm the repo URL is `rest://user:pw@host:8000/<user>/<repo>`
(e.g. `/discovery/tofu-state`), not `/tofu-state`.

## The one calendar item worth keeping

A **quarterly DR drill**, not a rotation — it catches silent key drift, which
kills you far more often than an un-rotated key does:

```sh
! just escrow-age-key-verify            # escrow still decrypts to the live key
# + confirm the off-premise copies are fresh:
ssh -p 2222 erik@voyager 'ls -1 /srv/backups/restic/discovery/*/snapshots/ | tail'
```
