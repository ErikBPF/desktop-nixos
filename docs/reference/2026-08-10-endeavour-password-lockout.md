# Postmortem: Endeavour password lockout

**Date:** 2026-08-10  
**Host:** `endeavour`  
**Impact class:** Local interactive access outage  
**Status:** Resolved; credential state aligned and subsequent upgrades healthy

## Summary

The primary incident was loss of password access to `endeavour` after a
declarative NixOS activation. `erik` is configured with
`users.mutableUsers = false` and a Sops-managed `hashedPasswordFile`, so each
activation makes the encrypted repository hash authoritative for
`/etc/shadow`.

At 07:09, the automatic NixOS upgrade successfully decrypted and installed the
committed password hash. That hash was structurally valid and matched both the
deployed Sops secret and the pre-recovery shadow state, but it did not represent
a password the user could successfully use. A known temporary recovery hash
was written to Sops working state and live `/etc/shadow`; decryption, hash
format, account unlock state, crypt verification, and Sops-to-shadow equality
then passed.

Sops did not corrupt the hash during decryption. The failure was credential
drift: declarative state contained a valid but unexpected password hash, and
activation correctly enforced it. Available evidence cannot determine whether
the expected password had previously been changed only with `passwd`, or the
wrong credential was encoded when the declarative hash was last updated.

After password recovery, a separate UWSM compositor failure returned successful
SDDM logins to the greeter. Direct Hyprland login worked. That was a secondary
desktop-session incident, not part of the password root cause.

## Resolution verification — 2026-08-16

Value-free checks confirmed:

- the repository Sops hash, deployed secret, and `/etc/shadow` agree;
- the account is unlocked;
- `nixos-upgrade.timer` is enabled and active;
- the latest `nixos-upgrade.service` completed successfully; and
- the current boot imported `/etc/ssh` host keys during initrd Sops setup, with
  both system and Home Manager secret activation completing successfully.

At incident time, live `/etc/shadow` and the active generation's deployed secret
differed, so another activation could have restored the unusable credential.
That immediate recurrence risk is now closed.

## Impact

- Password login for the primary interactive user failed.
- Graphical and TTY password access were affected until recovery.
- Existing privileged access was required to repair `/etc/shadow` safely.
- Recovery temporarily used a known low-entropy credential that must be rotated.
- No service data loss or evidence of unauthorized access was observed.
- Exact user-visible outage duration was not recorded.

## Evidence

No password or hash values are recorded here.

- `modules/user.nix` sets `users.mutableUsers = false`.
- The same module sets `users.users.erik.hashedPasswordFile` to the
  `hashed_password` Sops secret and marks it `neededForUsers = true`.
- Current and committed Sops files decrypt successfully with authenticated
  metadata.
- Both committed and recovery values are valid modular-crypt hashes.
- `/run/secrets-for-users/hashed_password` matches the committed repository
  hash from the active generation.
- The pre-recovery shadow backup matches that same committed hash.
- The recovery Sops value matches current live `/etc/shadow`.
- The recovery changed the hash; it was not merely an account unlock.
- Git attributes the previous `hashed_password` value to commit `3eb22b8`
  (`feat(fleet): codify rebuilt host state`) from 2026-07-14.
- No dedicated post-deployment password-login canary was recorded for that hash.

Together, these facts rule out ciphertext corruption or malformed hash output.
They prove that a valid declarative hash became live and did not match the
credential the user expected.

## Timeline

All times are local on 2026-08-10.

- **06:55:41:** boot activation started.
- **06:55:41–06:55:42:** `setupSecretsForUsers` and `setupSecrets` failed
  because system Sops configuration tried to read
  `/home/erik/.config/sops/age/keys.txt` before it was available.
- **07:09:59:** scheduled `nixos-upgrade` switched to the current system and
  successfully ran Sops secret installation.
- **07:09:59:** shadow backup timestamp coincided with activation; that retained
  state matches the committed Sops hash.
- **After 07:10:** expected password was rejected.
- Account, Sops, and shadow state were inspected without printing secret values.
- A known temporary recovery hash was installed in encrypted Sops working state
  and live `/etc/shadow`.
- **07:20:12:** live shadow state reflected the recovery.
- Crypt verification, unlocked account state, and Sops-to-shadow equality passed.
- Password authentication then succeeded.
- Successful SDDM authentication still returned to the greeter because the
  default `hyprland-uwsm` session exited; direct Hyprland login succeeded.

## Root cause

### Primary root cause: declarative credential drift

Repository state, not an interactive `passwd` change, owns the account password:

```nix
users.mutableUsers = false;
users.users.${username}.hashedPasswordFile =
  config.sops.secrets."hashed_password".path;
```

The active generation successfully decrypted a valid stored hash and enforced
it. The user did not have a working password corresponding to that hash.

The exact origin of the mismatch is unknown. Password plaintext is correctly
not stored or audited, so evidence cannot distinguish between these cases:

- password changed interactively but not synchronized back to Sops;
- unintended password supplied during the 2026-07-14 declarative rotation;
- intended password later forgotten or confused with another credential.

These are credential-provenance possibilities, not proven individual causes.
The systemic cause is clear: a password-hash change could become authoritative
without a fresh-login canary proving the operator knew the corresponding
password.

### Contributing defect: boot-time Sops key depends on user home

System Sops configuration points to:

```text
/home/erik/.config/sops/age/keys.txt
```

The password secret is marked `neededForUsers`, so it must decrypt before user
setup. Depending on a key inside that user's home creates an ordering cycle.
The boot journal showed this exact failure. A later activation succeeded only
after the home directory became available.

This defect did not alter the hash or cause the credential mismatch, but it
makes password recovery and early activation unreliable.

## Five whys

1. **Why did password login fail?** PAM checked against a hash that did not
   correspond to the password the user entered.
2. **Why was that hash active?** NixOS activation enforced the Sops-backed
   `hashedPasswordFile` with `mutableUsers = false`.
3. **Why was an unexpected hash allowed to become authoritative?** Rotation had
   no required fresh-login canary or deployed-state comparison.
4. **Why could an interactive password change drift?** `passwd` changes live
   shadow state only; the next activation restores declarative Sops state.
5. **Why was recovery fragile at boot?** System Sops decryption depended on a
   key located under the user home it was needed to create.

## Resolution

Completed recovery steps:

- Replaced the declarative password hash with a known temporary recovery hash.
- Applied the same hash to live shadow state without printing it.
- Confirmed Sops decryption and valid modular-crypt format.
- Confirmed account was unlocked.
- Confirmed the recovery password cryptographically matched the hash.
- Confirmed Sops and live shadow hashes matched.
- Kept unrelated encrypted secret changes intact.

Closure verification:

- The rotated repository hash is deployed and matches live shadow state.
- Password authentication succeeded during recovery.
- The account remains unlocked after subsequent successful upgrades.
- System Sops now uses a boot-available host key rather than a user-home key.

## Proposed guardrail: transactional password rotation

**Invariant:** a declarative password hash is not complete until the encrypted
value, deployed secret, live shadow state, and a fresh login all agree.

Required flow:

1. Rotate only through `just set-user-password`; do not use standalone `passwd`
   for a `mutableUsers = false` account.
2. Keep `hashed_password` in a host-specific Sops file so its ciphertext diff is
   attributable to password rotation rather than mixed with unrelated secrets.
3. Encrypt the system password secret to an `endeavour` host key available under
   `/etc/ssh` during early activation. Keep the user-home age key only for
   Home Manager secrets.
4. Before deployment, decrypt without printing, require a supported
   modular-crypt format, and verify the entered password against the decrypted
   hash.
5. After deployment, compare the Sops value, `/run/secrets-for-users` value, and
   `/etc/shadow` value in memory; report only `match` or `mismatch`.
6. Keep an existing privileged session open and require one fresh TTY password
   login before declaring success.
7. Abort or roll back if Sops setup fails, the account is locked, any hash
   comparison differs, or the fresh login fails.

Automated enforcement should include:

- a Nix/config test rejecting any `neededForUsers` secret whose decryption key
  is under `/home`;
- a focused test for the password-rotation recipe's confirmation, yescrypt
  generation, round-trip verification, and no-secret-output behavior;
- a deploy check that reports only secret presence, hash format, equality, and
  account lock status;
- an operational rule that auto-upgrade cannot be considered healthy after a
  user/password change until a fresh-login canary is recorded.

## Secondary issue: SDDM/UWSM greeter loop

After the password was repaired, PAM authentication succeeded but SDDM launched
`hyprland-uwsm`, Hyprland exited during multi-output DRM initialization, and
SDDM reopened the greeter. Logs contained:

```text
drm: Cannot commit when a page-flip is awaiting
```

Direct Hyprland login succeeded. Source mitigation changes SDDM's default from
`hyprland-uwsm` to `hyprland`. This matches upstream Aquamarine issue
[#343](https://github.com/hyprwm/aquamarine/issues/343), but remains separate
from password recovery.

## Follow-up actions

| Action | Owner | Status | Completion evidence |
| --- | --- | --- | --- |
| Pause auto-upgrade and avoid reboot until permanent hash is deployed | Host owner | Completed | Hashes aligned; timer enabled and healthy |
| Rotate temporary password with `just set-user-password` | Host owner | Completed | Password authentication succeeded; no value recorded |
| Deploy and compare Sops, deployed-secret, and shadow hashes | `desktop-nixos` | Completed | Three matching states and unlocked account verified 2026-08-16 |
| Split `hashed_password` into host-specific Sops file | `desktop-nixos` | Proposed | Password-only encrypted diff and focused ownership |
| Use boot-available host key for system Sops | `desktop-nixos` | Completed | Current boot imports `/etc/ssh` host keys and completes Sops activation |
| Add password rotation and `neededForUsers` regression checks | `desktop-nixos` | Proposed | Focused tests pass in CI |
| Keep direct Hyprland as SDDM default | `desktop-nixos` | Pending deployment, secondary | Successful direct SDDM login after deployment |

## Lessons

- Successful Sops decryption proves ciphertext integrity, not that the operator
  knows the password represented by a hash.
- With `mutableUsers = false`, `passwd` is temporary drift and the next NixOS
  activation will replace it.
- Password rotation needs a fresh-login canary while an existing privileged
  session remains open.
- `neededForUsers` secrets must use keys available before user homes.
- Authentication success and desktop-session success are separate checks; the
  later UWSM failure should not obscure the original password incident.
