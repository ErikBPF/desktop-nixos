# Hermes image and Argus lifecycle — native disposable fixtures

**Status:** backup gate waived; consumer publication/CI and rollout checks pending
**Stage / revision:** explicit rollout backup waiver; native fixture history retained / 5
**Owner / date:** desktop-nixos runtime slice / 2026-10-15 UTC
**Checkout:** `worktrees/hermes-agent-hardening`, `feat/hermes-agent-hardening`

## Outcome and why

Continue authorized Discovery rollout without backup/rehearsal prerequisite.

> what are we backing up? No need to backup these agents. Just continue

The explicit waiver supersedes the former operational gate, not synthetic proof
limits. Image rollback does not rewind mutable state. No further backup/preflight,
rehearsal/restore/deletions; optional helpers/tests/contracts and snapshots remain.
Inference budgets stay closed.

Human seed: “lets do both. Also check our litellm health”. Accepted corrections:
Argus accepts firing/resolved but never auto-archives from resolved; preserve
operator permissions and unrelated services. This slice implements only the
authorized consumer image pins, Argus lifecycle template/filter, and public
disposable compatibility fixtures. Publication, merge and deployment belong to
the coordinating session, not this implementation.

Argus and Romozinha now pin official manifest index
`sha256:444b42594e7f467425872fc35e077a227d377f0fe0726bc818706d62175fad8b`.
Native CLI reports v0.21.7; `/opt/hermes/install-stamp.json` attributes embedded
source to stable release commit `71d34bad1045610252eda02ee79549436896e784`.
Verified amd64 child is
`sha256:3140cc382d3f21a18019d28a1f89efb2af21ae9f86364895ccc019c7c7f8a446`;
Discovery targets x86_64-linux. Missing image labels are not provenance evidence.
Daedalus deliberately retains its old pin.

## Changes and evidence

[Runner](../../tests/hermes-agent-runtime.py) binds the
[behavior contract](../behaviors/hermes-agent-runtime.feature). Source-pin RED
asserted the old Argus pin; native route RED rejected resolved using the actual
v0.21.7 `WebhookRouteProcessor`. Both preceded production changes. NEW native
GREEN proves known-status admission and missing/null/unknown rejection, template
rendering with metadata beyond RAW truncation, native identity/admission helper
dedup, real plugin discovery/callbacks and terminal pre-tool caller consumption
of RTK modify directives. Only the unavailable external rewrite-command boundary
is doubled; executed command is synthetic `/bin/echo`.

The full runner now also proves OLD v0.21.0 and embedded revision
`562ee8ab76a703b7f524172cae0b1d52f9f94bd3`, OLD/NEW native plugin compatibility,
and the synthetic state roundtrip. OLD creates a session/message; NEW reopens a
disposable copy and appends; OLD's actual `SessionDB(read_only=True)` reads both
messages without changing database bytes; OLD appends on a separate writable
copy and verifies all three contents. SQLite integrity remains valid. OLD's real
middleware caller applies the rewrite before a synthetic guard veto; its execution
callback fails immediately if invoked. NEW's real pre-tool caller consumes the
same directive. Neither executes an agent terminal tool or contacts a provider.

Commands: `python3 tests/hermes-agent-runtime.py --config-only`, `--route-only`,
and `--new-only`. Full command requires both images and prints
`PASS hermes-agent-runtime` only after every gate succeeds. Partial command prints
`PASS hermes-agent-runtime-new-only`, never full-runtime success.

Receipts live under approved temporary `agent-validation-20261014/` with mode
0600: `runtime-image-red.txt`, `runtime-route-red.txt`, and final
`runtime-final-green.json`. Initial harness repairs corrected filter extraction,
the stamp path/CLI flag, and callback keyword; static checks caught Nix's reserved
`in` keyword, now correctly quoted. Image attribution receipt is
`official-image-validation-1dtdey31/official-image-provenance-continuation.json`.
Every fixture container uses `--network none`, `--read-only`, tmpfs `/tmp`, isolated
`HOME`/`HERMES_HOME`, and read-only binds of this public runner plus public plugins
only. No live home, config, credential, persona, memory or DB is mounted.

Continuation preserves the initial draft in
`runtime-transport-continuation-first-draft.json`. Attempt 1 exposed the mounted
script's OLD helper import-path mismatch; source-root native imports succeeded.
The fixture now uses that native source root, without copying or substituting
upstream modules. OLD's different middleware interface and pre-veto `dispatched`
semantics required two bounded hook-fixture repairs. Attempt 3 returned exit 0
and `PASS hermes-agent-runtime`; receipts retain every failed attempt. Final
checkpoint: `runtime-continuation-checkpoint.json`.

## Decisions, limits and continuing gates

Native renderer supports `{groupKey}`, `{status}`, `{receiver}`, `{externalURL}`;
RAW is the first 4000 characters, not guaranteed complete JSON. Missing metadata
remains an unresolved placeholder; no parser or header transform was invented.
Resolved is explicitly RECOVERY UNVERIFIED and never closure/archival authority.
Empty Discord/webhook tools, disabled terminal/kanban, and disabled backfill remain.

Independent review found that native scalar metadata interpolation uses literal
`str(value)`, unlike JSON-rendered RAW. A native adversarial fixture with newlines,
quotes, backticks and instruction-like text observed assertion-failing RED against
the previous late cue. The minimal fix moves an all-metadata-and-RAW untrusted cue
before the first placeholder and explicitly denies action/recovery authority.
The fixture preserves literal scalars and checks cue ordering for benign and
adversarial payloads. This is a presentation cue, not scalar escaping or prompt
injection immunity. Empty toolsets and native authentication remain the security
boundary. Receipts: `runtime-cue-red.json` and `runtime-cue-checkpoint-revision2.json`.

Dedup is a one-hour in-memory cache keyed by profile, route and delivery ID.
Different IDs admit transitions/new episodes/unchanged repeats; expiry/restart
forgets IDs. Helpers prove consumer admission, not publisher ID generation or
network-delivered replies. Grafana Discord routing remains unchanged. Native
health, inference, final platform delivery and telemetry are separate gates.

First OLD immutable-image pull exhausted its 450-second budget (infrastructure
failure, not RED). User authorized one further amd64 immutable pull; that completed.
No third pull occurred. The constructor-created synthetic schema roundtrip passes;
it does not establish all historical migration shapes or private-state coverage.
Leaf publication and the selective consumer pin now resolve to 0.2.77, merge
`1c28c4953e1a88bd410c0e4bb3cb000162a2b361`. An earlier Discovery closure built on
Orion; latest-source dry-run plans fourteen derivations, not yet built. No activation occurred.
The full OLD/NEW fixture receipts above predate the final guard repairs. Current
guard validation uses the installed v0.21.7 SDK/finalizer with synthetic state;
see the [hardening checkpoint](hermes-agent-hardening-one-pager.md).

The separately authorized production backup attempt failed after 353.237 seconds
with `ValueError` / `remote-unobserved`; snapshot identity and isolated restoration
remain unconfirmed. A subsequent fixed-unit GET observed both writers running,
Argus's timer waiting and Romozinha's timer absent. This establishes availability,
not historical prior-state equality. Backup budget is closed; operational
backup/rehearsal gates are waived by the latest quoted direction, recorded in
`hermes-scoped-backup-attempt2-vz14doea/rollout-backup-waiver.json` under the approved
temporary root. Consumer publication, protected CI/latest build, actual
deployed-baseline drift review and post-activation health/version remain gates;
no new inference budget. See the [backup checkpoint](hermes-state-backup-one-pager.md).
Recovery retains old image pin
`sha256:d7800dcb7fe821ba5fb7ec594724a07d3fa972ee2e37092cc9fb8265185c7868`;
no automatic live-state downgrade is authorized.
