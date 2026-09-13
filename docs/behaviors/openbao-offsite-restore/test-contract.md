# OpenBao offsite restore — PL and IP

## Accepted scope and human seed

[behavior.md](behavior.md) preserves the user's implementation instruction verbatim.
It accepts the next implementation recommended in Homelab's September 13
proposal batch: a pinned Voyager snapshot through the existing isolated drill.
This refines that existing proposal; it does not originate a new recovery system.

Source baseline: `cdb44395`, `modules/hosts/discovery/vault.nix:575–664`.
The drill already enforces a 48-hour local-source limit, uses loopback
18200/18201, verifies restore/unseal/AppRole and updates a success metric.
The Voyager backup at lines 730–744 already owns repository and password files.

## PL — grounded grill and decision map

- Q-1: Does “offsite restore” require a new verifier? No. The existing local-input
  drill already supplies the desired verification. Replace its input, not the
  verifier or schedule.
- Q-2: Does “source age” mean upload time? No. The current `find -mmin -2880`
  grades the source file. Grade the archived file's timestamp, reject future
  values and ages at or above 172800 seconds; snapshot upload time is insufficient.
- Q-3: Does “recover the secrets service” establish independent cold bootstrap?
  No. Existing SOPS key and AppRole material remain prerequisites. Independent
  credential custody and loss of Discovery are explicitly outside this slice.

Bounded party exchange: the operator favors using the existing quarterly job;
the security reviewer requires remote provenance and no local fallback; the
developer rejects a second scheduler and duplicated verifier; the tester requires
failure preservation and an exact-ID retrieval assertion. Existing code resolves
these choices. The exact cause of the separate Servarr stale lock is unrelated.

Decision: select the newest Voyager snapshot for the fixed OpenBao source path,
validate a single full hexadecimal snapshot ID, inspect the exact archived file,
and retrieve only that file into owned private scratch. Use existing credential
file settings without printing values. Do not restore a remote directory tree.
Keep native repository integrity checks, current loopback verification and the
quarterly schedule. No local, SFTP or B2 fallback. A remote failure must be visible.

Alternatives rejected: another restore service duplicates isolation and metrics;
an operator workstation handoff adds sensitive-data transport; upload-age checks
misrepresent stale Raft contents; a new backup tier or HA topology is unnecessary.

Risks: source metadata validation, credential exposure in stderr/argv, partial
downloads, process cleanup on failure, interrupted runs, false success metrics,
and current AppRole credentials failing against an older snapshot. Such failure
is a recovery failure, not grounds to weaken the authentication check.

No unresolved product choice blocks implementation. The 48-hour threshold and
cadence are inherited; no Authentik 24-hour policy is transferred to OpenBao.

Second grill round: the existing readiness probe could accept another listener
on the drill port. Reject occupied drill ports before startup and check the
spawned child remains alive before submitting credentials. Set `umask 077`
before any private output and install cleanup before retrieval. Correct the
runbook's known-secret-path claim: the existing verifier checks AppRole login,
not secret-value reads. These are safety/accuracy corrections within this slice.

## IP — one vertical slice

Observable result: the existing drill proves recovery from a single identified
Voyager copy and preserves its last success when any stage fails.

Public test seam: execute the actual inline ExecStart body with synthetic Restic,
OpenBao and HTTP commands, following `tests/openbao-probe/test_probe.py`. This
grades command orchestration and evidence handling without production secrets;
it cannot prove a real remote repository or Raft restore. Keep implementation in
the existing Nix unit; no standalone shell module or new BDD/test dependency.

RED: add `tests/openbao-offsite-restore/test_restore.py`; run
`python3 -m unittest discover -s tests/openbao-offsite-restore -v` against the
unchanged unit and observe missing remote retrieval/provenance failures. Commit
the red checks as an anchor before implementation.

GREEN: change only the drill's input preparation, credential environment, bounded
runtime and metadata-only success receipt in `vault.nix`. Preserve existing
restore/unseal/authentication logic and success metric name. Add source freshness
to the same atomically published metric file only after successful verification.
Wire the focused test into existing CI and update the canonical recovery runbook.

Executable coverage:
- fresh remote source succeeds with exact-ID metadata lookup and download;
- changing “latest” after selection cannot change the retrieved snapshot;
- unavailable/empty/ambiguous snapshots and invalid IDs fail before restore;
- wrong path, symlink/non-file, empty and invalid timestamp metadata fail closed;
- future, exactly-48-hour and older file timestamps fail; a fresh upload cannot
  rescue stale source data;
- partial download and restore/unseal/auth failures preserve previous metrics;
- cleanup removes owned scratch and process; output contains no synthetic secrets;
- occupied drill ports or a dead spawned process prevent credential submission;
- source timestamp and Voyager/snapshot receipt appear only on success;
- Nix evaluation preserves schedule, loopback endpoints and credential-file wiring.

Verification: focused checks, existing relevant OpenBao checks, ShellCheck of the
rendered script, `just lint`, `just fmt-check`, `just docs-check`, and
`just dry discovery`. Do not run `nix flake check` locally. Final RV uses independent
security/reliability/test review plus source conformance and simplicity checks.

Rollout: reviewed published revision through the documented Discovery deployment
recipe, then `just openbao-restore-drill`. Record the exact snapshot/source age
and verify production health before and after. A local synthetic test is not a
live restore receipt. Publication and live acceptance are reported separately.
Rollback uses the same source/deploy route to restore the previous input path;
never roll back production Raft state or delete repository data.

Plan grill: native single-file retrieval minimizes path exposure; preserved
AppRole checks catch unusable snapshots; systemd serializes this unit and fixed
loopback ports detect conflicts. Bound execution and handle interruption
without broadening success criteria. Review again only for new evidence.

## Final validation receipt — 2026-09-13

- Focused executable checks: 2 tests with 21 negative subcases pass, including
  actual TERM interruption during retrieval and isolated-child operation.
- Rendered inline shell passes ShellCheck. Effective Discovery unit evaluation
  confirms the existing repository/password credential-file paths, `PrivateTmp`,
  `ProtectHome` and a 15-minute timeout. Quarterly `05:30` scheduling, persistence
  and one-hour random delay remain unchanged.
- `just lint`, `just fmt-check`, `just docs-check` and `just dry discovery` passed
  with exit 0. Final independent review reported no blocking findings.
- The broader Discovery contract suite retains four unrelated failures reproduced
  at baseline `cdb44395`; that baseline also had a stale generated source hash.
  This change regenerates the source-hash artifact without changing its contract.
- Publication and the live Voyager restore acceptance remain pending. Synthetic
  checks establish orchestration behavior, not a production recovery receipt.
