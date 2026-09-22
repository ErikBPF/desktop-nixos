# Endeavour manual upgrades

**Stage / revision:** GREEN / E2E / feedback reconciliation / 8
**Status:** recovered and runtime-verified; PR delivery in progress
**Owner / date:** desktop-nixos / 2026-09-22

## Outcome and changes

Human seed: "lets run a just upgrade and lets remove endeavour host from nightly auto-updates"

Endeavour runs the upgraded system configuration. Its nightly upgrade service
and timer are absent and inactive. The final `just switch endeavour` exited 0.
Subsequent user feedback revealed that the switch regressed OpenCode's database
bindings. Healthy services did not establish preserved conversation access.
The existing main-line fix has since been activated; both backend APIs again
return historical conversations. Recovery details follow below.

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

OpenCode database bindings are restored. Reboot at the user's convenience to replace the
running 7.1.10 kernel with installed 7.2.6; no reboot was performed. The managed
OpenCode binary reports 1.18.31, but an existing standalone `opencode` entry in
the user's Nix profile still shadows it with 1.18.30. That personal entry was
preserved. Its removal is separate profile cleanup.

The user subsequently requested: "create prs and merge to main". Delivery uses
one desktop-nixos PR for the upgrade and timer removal. The branch incorporates
the newer main-line workspace database isolation fix. Initial deployment evidence
predates that change; the recovery deployment below includes it. CI validates
the combined PR candidate.
Future deployment of an older configuration can restore nightly upgrades.
Keep the OpenCode toolchain pin
aligned with its publisher when updating that input. The prior system generation
remains the recovery reference; no rollback or garbage collection was performed.

## Feedback: missing OpenCode sessions

Human correction: "all my opencode sessions disapeared. Check what weve done";
the user clarified that both saved conversations and running terminal sessions
appeared missing. Publication and merge were paused before PR creation.

The deployed detached checkout lacked the database-isolation change in main
commit `b91c816c` (PR #353). Activation restarted both OpenCode backends at
11:32:35 -03 without their explicit `OPENCODE_DB` settings. At diagnosis, both processes
held file descriptors for `opencode-stable.db`, which contained zero sessions
and zero messages. The original `opencode-homelab.db` contains 346 sessions and
20,966 messages; `opencode-dataplatform.db` contains 251 sessions and 15,366
messages. Both passed read-only SQLite `PRAGMA quick_check`.

All 16 sessions on tmux's `workspace-desktop` socket still exist with live
OpenCode panes; none is attached. This establishes that the tmux sessions and
stored histories remain, not that in-flight model operations survived the
backend restart. No conversation contents were read and no database was edited.

The delivery branch already included main's correct database bindings after
rebase, but that revision had not been activated. The recovery plan was to activate those
existing declarations and verify each backend opens its original database,
then verify session visibility. Database deletion or replacement is unnecessary.

Follow-up seed: "new tui on new shell still doesnt find anything using ol/ow commands. Check why".
Fresh interactive-shell lookup resolves the installed `ol`/`ow` wrappers, which
attach to the existing localhost backends on ports 4096/4097. Both backend
health endpoints reported healthy OpenCode 1.18.31, but their session endpoints
returned zero records. Both services still lacked `OPENCODE_DB` in their effective
environment. A fresh client therefore attaches to the same empty backend;
opening a shell does not activate the source configuration or restart services.
This attachment path uses the managed profile wrappers, so the standalone
OpenCode 1.18.30 PATH entry does not explain these empty session lists.

## Recovery verification

The user's "continue" authorized proceeding with recovery and delivery. Before
activation, SQLite backup copies of both original databases were created under
`~/.local/share/opencode/recovery-20260922.Z5oyYw/` (directory mode 0700,
database files 0600); both backups passed `PRAGMA quick_check`.

`just dry endeavour` and `just switch endeavour` passed on the rebased branch.
The active system is now
`/nix/store/ayjas42z1k02hx200iilgwcf8mggc6k1-nixos-system-endeavour-26.11.20260922.6774f7b`.
Both effective service environments contain their correct `OPENCODE_DB` path.
The directory-specific session API calls used by the clients each return 100
records with the default page limit, rather than zero. All 16 tmux sessions
remain present; system and user managers report no failed units. The nightly
upgrade timer remains absent and inactive. No database restore, deletion, or
history rewrite was needed.

Pending user confirmation: whether fresh `ol` and `ow` clients display the
expected conversations. API recovery is observed; interactive rendering and
resumption of interrupted model operations are not established by these checks.
