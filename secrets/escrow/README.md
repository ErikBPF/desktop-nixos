# age-key escrow

Off-fleet, off-premise escrow of the **sops age key** — the fleet's single
root of trust. See `docs/proposals/2026-06-30-offsite-dr-crown-jewels.md` §4b.

## What lives here

- `age-key.age` — the sops age key (`~/.config/sops/age/keys.txt`) encrypted as
  a **passphrase-sealed** age blob (`age -p`). It is ciphertext: safe to commit
  and to copy off-premise, useless without the passphrase.

## Why committing it is safe

`age -p` uses a scrypt recipient — the blob can only be opened with the
passphrase, which lives **only** in a password manager + one offline copy,
never on any fleet host and never in git. Losing the git repo (or GitHub) does
not expose the key; losing the passphrase makes the blob unrecoverable **by
design** (that is the security property).

`.sops.yaml` does not match this path, so sops never touches the blob.

## Create / refresh / verify

```sh
! just escrow-age-key          # interactive: encrypt + self-verify round-trip
just escrow-age-key-push       # copy off-premise to voyager (~/escrow)
! just escrow-age-key-verify   # quarterly DR drill: blob still decrypts to live key
```

`age -p` needs a real TTY — run the interactive recipes with a leading `!` (or
in a normal terminal), never over a non-tty pipe.

## Recover (house gone, only the passphrase in hand)

```sh
age -d age-key.age > ~/.config/sops/age/keys.txt   # from git or voyager:~/escrow
chmod 600 ~/.config/sops/age/keys.txt
# age key restored → sops decrypts everything else → restic restore → redeploy
```
