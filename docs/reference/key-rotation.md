# Key rotation

**Status:** Reference (as-built, 2026-06-30).

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

**Key model (as-built).** `sops.age.keyFile = ~/.config/sops/age/keys.txt` on
every host (`modules/services/sops.nix`). The **`primary`** key (the workstation
key) is staged onto **most** hosts — discovery, kepler, pathfinder, voyager,
telstar, laptop. **`orion`** and **`archinaut`** hold their **own** keys (they
are separate recipients in `.sops.yaml`) and are unaffected by rotating primary,
provided they stay recipients. Rotating primary = re-key every primary host.

> **TRAP — a redeploy does NOT distribute the key.** `first-boot.nix`'s
> `distributeSopsKey` copies the staged key **only if the target doesn't exist**
> (`[ ! -f "$TARGET" ]`), then deletes the staging file. On a live host the key
> already exists, so **`switch`/`deploy-rs` never overwrite it.** There is no
> repo→deploy path for the private key on running hosts — distribution is a
> manual `ssh` write to each host's `~/.config/sops/age/keys.txt`. A `keys.txt`
> may hold **multiple** identities (one `AGE-SECRET-KEY-…` per line); sops tries
> each, which is what makes the additive phase safe.

**Phase A — additive, zero brick window (old key still works throughout):**
1. Generate: `age-keygen -o /tmp/new-primary.txt`; note its public key
   (`age-keygen -y /tmp/new-primary.txt`).
2. **Add** the new recipient to all three `.sops.yaml` (keep old primary + orion
   + archinaut) — `desktop-nixos/.sops.yaml`, `homelab-iac/.sops.yaml`,
   `servarr/.sops.yaml`.
3. `sops updatekeys <file>` for every encrypted file in all three repos → now
   decryptable by old **and** new. (`rtk proxy sops`; verify key counts.)
   Commit + push all three.
4. **Distribute** — append the new key line to `~/.config/sops/age/keys.txt` on
   **each primary host** (discovery, kepler, pathfinder, voyager, telstar,
   laptop) + the workstation. e.g. per host:
   `ssh -p 2222 erik@<host> 'cat >> ~/.config/sops/age/keys.txt' < /tmp/new-primary.txt`
   (append, do not overwrite — the old key must remain until Phase B).
5. **Verify every host still decrypts** before proceeding: on each,
   `sudo systemctl restart <a sops-consuming unit>` or re-run
   `/run/current-system/activate` and confirm `/run/secrets/*` populate and no
   sops-nix failure. Do **not** enter Phase B until all hosts pass.

**Phase B — retire the leaked key (makes the old blob worthless):**
6. **Remove** the old primary recipient from all three `.sops.yaml`.
7. `sops updatekeys` every file → now new + orion + archinaut only. Commit + push.
8. Redeploy / re-activate each host (now decrypting with the new key only);
   confirm `/run/secrets` still populate.
9. Cleanup: remove the old key line from each host's `keys.txt`; `shred` the
   workstation's old key material and `/tmp/new-primary.txt`.
10. **Re-escrow:** `! just escrow-age-key` (fresh strong passphrase) →
    `just escrow-age-key-push` → `just escrow-secrets`; verify with
    `! just escrow-age-key-verify`.

**Ordering / safety notes.**
- **laptop is session-risky** (a `switch` can disrupt the GUI session — repo
  rule: no unprompted GUI restart). Append its key + re-activate in a controlled
  window, or use `boot` + a planned reboot.
- **`autoUpgrade` (05:00 daily) pulls `main` + rebuilds.** Between a Phase-B push
  and a host getting the new key, an autoUpgrade would try to decrypt new-only
  secrets with a host still on the old key → activation fails. Complete Phase A
  distribution to **all** hosts first; run Phase B in one sitting.
- orion/archinaut: leave their own keys as recipients throughout; nothing to do
  on them unless you're also rotating *their* keys.

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
