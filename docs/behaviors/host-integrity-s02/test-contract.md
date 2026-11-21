# S02 test contract and implementation evidence

## Scope

Use real subprocesses with harmless stub commands and temporary files for store
exit bitsets, updater no-op/stale database, AV findings, partial coverage, command
errors, deadline, process descendants, contention, receipt expiry and service
failure. Validate Nix service/timer wiring with a synthetic enabled module and
explicit budgets. No actual host scan or activation is permitted.

## Chronology and initial limitation

The initial helper-existence assertions failed before implementation, but the
packet explicitly excludes missing proposed files from behavioral RED. Those
failures are a harness milestone, **not behavioral RED**. The first substantive
runner draft then passed 36 combined runner/reporter tests. This is a TDD
ordering deviation, retained here rather than retroactively relabelled. No
completed implementation was temporarily removed to manufacture a RED anchor.

Subsequent negative tests exposed actual defects and failed before repair:

| Regression | Observed failure | Kept repair |
|---|---|---|
| Batch startup cost | Two scanner invocations, expected one | One private file-list batch |
| Mutable path escape | Scanner read `OUTSIDE SCOPE` after replacement | Secure descriptor traversal and bounded private copy |
| Finding before timeout | Finding count zero | Incremental durable progress |
| Limits/encrypted coverage | Finding count one, expected zero | Separate coverage heuristic classification |
| Exited parent/child stdout | Child remained sleeping after deadline | Always terminate the command process group |
| Malformed exit 1 plus exclusion | Partial instead of failed | Require recognized scanner output independently |
| Peer receipt retention | Store expiry deleted AV receipt | Per-check retention matching |
| Service bootstrap failure | No restricted receipt | Failure handler persists receipt |
| Timeout investigation | Receipt lacked observed signature | Preserve matched private evidence while streaming |
| Updater/AV concurrency | Updater launched under shared scan lock | Exclusive updater/shared scanner database lock |
| Heavy-job overlap | Store and AV launched under held lock | Shared exclusive heavy-job lock |
| Incomplete database install | Missing main/bytecode still returned complete | Require full main/daily/bytecode set before AV |
| Abandoned copy recovery | Old private batch remained | Remove only per-job abandoned batch directories |

Additional passing checks cover malformed/future daily headers, actual selected
version, aggregate copy cap, retained complete timestamps, real open failures,
vanished/oversized files, symlinks, private source mapping and output cleanup.
Permission failure is injected at the OS-open seam rather than assuming mode
000 is unreadable to root. Reporter running-progress regression first failed
with an unsupported event, then passed after the event was added.

## Command policy evidence

Local pinned `nix store verify --help` establishes exit bits 1 (corrupt),
2 (untrusted), 4 (other verification failure). Configured `--no-trust` limits
production policy to content integrity; the parser handles unexpected bitsets
conservatively. Local pinned ClamAV 1.5.4 help confirms explicit symlink,
filesystem and limit flags.

[ClamAV 1.5.4 scanfile source](https://github.com/Cisco-Talos/clamav/blob/clamav-1.5.4/clamscan/manager.c)
resolves paths before reopening them. Passing inherited `/proc/self/fd` paths
would therefore not close the mutable-path race; bounded private staging is
necessary for the chosen CLI boundary. Its numeric filenames also prevent
untrusted source filenames from injecting result lines.

A disposable smoke test used that exact pinned ClamAV executable, a tiny local
`.ndb` signature and two harmless temporary files with the final explicit flags
and file-list mode. It returned exit 1, one clean `OK`, and one
`FixtureSignature.UNOFFICIAL FOUND`. It used neither system databases nor host
content and performed no network fetch. This is CLI compatibility evidence, not
a deployed host scan or coverage-performance claim.

The CLI contract also runs the real helper entrypoint against a failing fixture
tool: normal process exit, failed gauge state and one execution error. Unit
success is not interpreted as clean coverage; the independent unit-failure
handler is reserved for failures the runner could not handle.

The full database-set correction followed two observed failures: missing main
and missing bytecode both produced complete state. Both now fail before AV;
private receipts record the selected full set and freshness still uses daily.
The final pre-integration runner/reporter subset passed **53 tests** in 5.18s.

Linux ABI evidence: the [openat2 UAPI flags](https://github.com/torvalds/linux/blob/master/include/uapi/linux/openat2.h)
define no-symlink and no-mount-crossing resolution; the
[generic syscall table](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/unistd.h)
and [x86_64 table](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl)
assign syscall 437. Local x86_64 tests exercise that boundary; no aarch64
runtime claim is made.

## Final integrated validation

The module agent captured assertion RED in `/tmp/s02-module-red.log`: the
synthetic enabled fixture expected the `jobs` option before it existed. The
implemented fixture then validated finite resource limits, timer persistence and
jitter, private runtime directories, separate OnFailure wiring, disabled default,
job/check mismatch rejection and empty AV scope rejection. Its GREEN marker is
`S01_MODULE_EVAL_OK S02_MODULE_EVAL_OK` (`/tmp/s02-module-green.log`).
AV preserves visibility of declared `/tmp` scopes while using its own private
runtime directory for scanner scratch; it cannot silently scan a substituted
empty PrivateTmp namespace.

Final frozen commands from this checkout, 2026-11-20:

- `ALLOY_BIN=/nix/store/fz2k4zjxinpq07kqzijgmxgy9dlmayyy-grafana-alloy-1.21.3/bin/alloy pytest -q tests/host-integrity tests/alloy --tb=short`: **57 passed, 14.88s**.
- `just lint && just fmt-check && just structure-check`: passed; existing size advisories only.
- `nix eval --offline --impure --raw --file tests/host-integrity/evaluate.nix`: both S01/S02 success markers.
- `nix build .#nixosConfigurations.endeavour.config.system.build.toplevel --dry-run --offline`: exit **0**, raw local log `/tmp/host-integrity-s02-host-dry.log`; no build or activation.
- `git diff --check`: passed.

Independent reviews found no remaining material source findings after repairs.
These gates do not prove deployed systemd execution, real scan performance,
notification delivery or aarch64 runtime behavior. Durable progress counts
survive abrupt termination, but detailed receipt data is finalized only on
handled completion/failure; OOM/SIGKILL can therefore leave a retained finding
without its full signature/source detail. Handled command timeouts preserve
those details and have a passing regression.
