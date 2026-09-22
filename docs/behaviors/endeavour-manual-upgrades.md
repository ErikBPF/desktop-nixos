# Endeavour manual upgrades

**Stage / revision:** GREEN / E2E / delivery / 6
**Status:** complete; reboot pending for the new kernel
**Owner / date:** desktop-nixos / 2026-09-22

## Outcome and changes

Human seed: "lets run a just upgrade and lets remove endeavour host from nightly auto-updates"

Endeavour runs the upgraded system configuration. Its nightly upgrade service
and timer are absent and inactive. The final `just switch endeavour` exited 0.

Endeavour now declares `system.autoUpgrade.enable = false` in
[its host configuration](../../modules/hosts/endeavour/default.nix). The obsolete
schedule and unattended-upgrade settings were removed. The
[installation guide](../guides/install.md#fleet-auto-update) documents manual
upgrades. Other hosts' upgrade settings are unchanged. `just upgrade` refreshed
`flake.lock`. The new nixpkgs removed `services.journald.extraConfig`, so the
shared journal configuration and Discovery, Kepler, and Orion overrides were
migrated to `services.journald.settings.Journal`, retaining their limits and
the upstream `Audit = "keep"` behavior.

## Evidence and limits

`just lint`, `just fmt-check`, `just docs-check`, and `just dry endeavour`
passed before the upgrade. Targeted Nix evaluation returned `false` for
Endeavour's `system.autoUpgrade.enable`. These checks establish configuration
validity, not activation. The first `just upgrade` failed fetching opencode-flake
because of transient DNS failure; a download probe succeeded and retry updated
the lockfile. That attempt then failed on the removed journald option before
activation. After the migration, `just dry endeavour` passed against the new
lockfile (1,258 derivations to build). `just switch endeavour` resumes the
upgrade using the repository's configured builders without refreshing inputs
again. Evaluation confirmed the 50M/10M fleet journal defaults and the larger
host overrides. Discovery, Kepler, Orion, Apollo, Archinaut, Archinaut base,
Pathfinder, Telstar, Vanguard, Voyager, and the Orion ESP installer passed
dry-checks. Other hosts have not been deployed.

The actual build then rejected OpenCode 1.18.31's fixed-output dependency hash:
expected `sha256-lk/fLbc+mU27slF3kuKwR5MYdoyKCA6lDeetOHyfP80=`, received
`sha256-rTBlyybJ+RNQWs7qIt9dX/x0jUYkUFp76HnwXoiQMnk=`. Activation did not run.
Restoring OpenCode 1.18.30 passed dry-check but failed the same dependency-hash
check during build. That experiment was reverted. Both attempts used Bun 1.4.2
from the consumer's updated nixpkgs through an input `follows` override.
The published OpenCode flake instead locks nixpkgs to
`3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2`. The consumer now explicitly pins
OpenCode's nixpkgs input to that published toolchain while retaining the latest
OpenCode 1.18.31. No dependency hash was overridden. Lint, formatting, and the
revised Endeavour dry-check passed. The dependency-hash check and full build
then passed. Other host dry-checks
used the earlier candidate; their journal migration is unchanged.

Activation initially returned exit 4 because Home Manager's Ponytail download
hit another DNS failure. Its configured automatic restart succeeded; a final
cached `just switch endeavour` exited 0. The active system is
`/nix/store/c5xnyss4n0g2hpz89l4gf5hh775vpv6w-nixos-system-endeavour-26.11.20260922.6774f7b`.
SSH, Tailscale, NetworkManager, journald, and Home Manager report success;
system and user managers report no failed units. Both `nixos-upgrade.service`
and `nixos-upgrade.timer` report `LoadState=not-found`, `ActiveState=inactive`.

Before the switch, `nixos-upgrade.timer` was enabled and active, and systemd
reported no failed units. The running system was
`/nix/store/bsk8va8hfx9qnplc733i22gp1b3ncgr5-nixos-system-endeavour-26.11.20260902.3ed67ec`.
The checkout started clean at detached HEAD `a6c8b89b`.

## Continuing work and recovery

No execution remains pending. Reboot at the user's convenience to replace the
running 7.1.10 kernel with installed 7.2.6; no reboot was performed. The managed
OpenCode binary reports 1.18.31, but an existing standalone `opencode` entry in
the user's Nix profile still shadows it with 1.18.30. That personal entry was
preserved. Its removal is separate profile cleanup.

The user subsequently requested: "create prs and merge to main". Delivery uses
one desktop-nixos PR for the upgrade and timer removal. The branch incorporates
the newer main-line workspace database isolation fix; deployment evidence above
predates that unrelated change. CI validates the combined PR candidate.
Future deployment of an older configuration can restore nightly upgrades.
Keep the OpenCode toolchain pin
aligned with its publisher when updating that input. The prior system generation
remains the recovery reference; no rollback or garbage collection was performed.
