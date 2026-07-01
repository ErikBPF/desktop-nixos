# age-key escrow

Off-fleet, off-premise escrow of the **sops age key** — the fleet's single
root of trust. See `docs/proposals/2026-06-30-offsite-dr-crown-jewels.md` §4b
and `docs/reference/key-rotation.md`.

## What lives here

- `age-key.age` — the sops age key (`~/.config/sops/age/keys.txt`) encrypted as
  a **passphrase-sealed** age blob (`age -p`). **Gitignored** (`secrets/escrow/*.age`).

## Why it is NOT committed

`desktop-nixos` is a **public** repo. A committed blob — even passphrase-sealed —
is world-readable ciphertext that anyone can brute-force offline forever, so its
only protection would be passphrase entropy against the whole internet. That is
too thin for the root of trust. The blob therefore lives **only** in two
places, both private failure domains:

- `voyager:~/escrow/age-key.age` (off-premise, Oracle, tailnet/break-glass only), and
- a **password manager** entry (cold-reachable from a fresh laptop).

The passphrase lives **only** in the password manager + one offline copy (kept
**off-premise**), never on any fleet host and never in git. Losing the
passphrase makes the blob unrecoverable **by design**.

> A `keys.age` was briefly committed to this public repo (git history retains
> it). If the passphrase is not high-entropy, rotate the age key — see
> `key-rotation.md`.

## Create / refresh / verify

```sh
! just escrow-age-key          # interactive: encrypt + self-verify round-trip
just escrow-age-key-push       # copy off-premise to voyager (~/escrow)
! just escrow-age-key-verify   # quarterly DR drill: blob still decrypts to live key
```

Then store the blob + passphrase in the password manager. `age -p` needs a real
TTY — run the interactive recipes in a normal terminal, not over a non-tty pipe.

## Recover (house gone, only the passphrase in hand)

```sh
# fetch age-key.age from the password manager, OR from voyager over break-glass:
#   ssh -i <escrowed-ssh-key> erik@<voyager-public-ip> 'cat ~/escrow/age-key.age' > age-key.age
age -d age-key.age > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
# age key restored → sops decrypts everything else → restic restore → redeploy
```
