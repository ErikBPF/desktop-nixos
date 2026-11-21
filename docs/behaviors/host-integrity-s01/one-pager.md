# S01: reporting boundary, first implementation draft

## Outcome and why

Host integrity has an opt-in reporting boundary that keeps evidence across
process restarts and incomplete runs. This matters because a newly published
metric is not proof that a scan finished, and a failed or clean rerun must not
hide an unresolved finding. No fleet host is enabled. The deliverable is the
reporting and collection foundation for S02's bounded jobs and S03's independent
coverage rules, not a deployed security claim.

## Changes

The small Python reporter stores each configured check's state privately and
atomically replaces its separate readable metric file. It emits the frozen
instance/check identity, never-run state, attempt/completion/publication times,
retained maximum finding count, and latest-attempt skips/errors. Signature
checks additionally expose the selected database timestamp. Input and persistent
state validation rejects malformed numbers and future timestamps. State is
persisted before metric replacement, allowing a restart to replay evidence if
publication was interrupted; no automatic finding-clear operation exists.

The NixOS module registers disabled-by-default configuration, root-owned private
state and metric directories, and a bounded startup service that restores
configured checks. It changes neither shared textfile ownership nor backup
producers. Alloy now rejects the reserved integrity namespace from the legacy
writable textfile stream. The enabled integrity collector uses its own directory,
forces configured host identity, accepts configured checks, and removes
non-contract labels. Explicit CI wiring provisions the pinned Alloy package and
includes the new tests and existing Alloy tests.

## Evidence and limits

Behavioral tests cover persistence, failure retention, malformed input and
injected atomic-replacement interruption. A synthetic enabled/disabled Nix
configuration asserts permissions, service wiring and collection boundaries.
Pinned Alloy 1.21.3 validates its complete generated configuration. A temporary
local collector fixture demonstrates that a legacy forged finding disappears,
an existing backup metric survives, and trusted identity is overwritten without
leaking private labels. This runs no host scan and sends no remote writes.

Initial assertion-failing tests preceded implementation. Harness repairs and
three additional malformed-state RED cases are preserved in
[test-contract.md](test-contract.md). Final combined suite: **19 passed**. `just lint && just fmt-check && just
structure-check` passed (existing size advisories only);
`nix eval --offline --impure --raw --file tests/host-integrity/evaluate.nix`
returned `S01_MODULE_EVAL_OK`. The final
`nix build .#nixosConfigurations.endeavour.config.system.build.toplevel
--dry-run --offline` passed with exit 0. Existing Rofi/PipeWire deprecation
warnings remain.
No production transport, notification or observation window has been tested.

## Decisions and continuing work

One private record and one metric file per check keep publication independent;
there is no new daemon or database. The existing pinned Python and Alloy packages
supply runtime dependencies. S02 will reuse this reporter rather than introduce
a second state representation. The deployment defaults remain disabled until
pilot host, reviewed mutable scope, budgets and retention decisions are settled.
Independent review found and repaired boolean database-time acceptance and a
fixture that explicitly disabled the module instead of testing its default.
The boolean regression failed before the fix and now proves neither persistent
state nor metric output changes on rejection. Final reviewer confirmation is
tracked by the coordinating agent.

## Risks and recovery

Unavailable storage can prevent even failure publication. Existing metrics then
remain, and independent stale/missing detection must catch that condition.
Interrupted publication preserves either the previous complete metric file or
the replacement; persistent state is replayed at startup. Corrupt private state
fails closed instead of clearing evidence. Reverting the opt-in module and Alloy
wiring removes the new path; retain private state until findings are explicitly
reviewed. No live activation or rollback was performed.
