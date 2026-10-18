# Hermes plugin and Romozinha configuration hardening

**Status:** backup prerequisite waived; consumer publication/CI and rollout checks pending
**Stage / revision:** explicit rollout backup waiver / 12
**Owner / date:** desktop-nixos / 2026-10-15
**Checkout:** `worktrees/hermes-agent-hardening`, branch `feat/hermes-agent-hardening`
**Base:** `880c25003d788c1c72f7cca6d9316195cfbd5178`

## Outcome and accepted boundary

Continue authorized Discovery rollout without a backup/rehearsal gate. Image rollback
does not rewind mutable state. Consumer publication, protected CI/latest build,
deployed-baseline drift and post-activation checks remain. Inference budget stays closed.

> what are we backing up? No need to backup these agents. Just continue

> lets do both. Also check our litellm health

> lets continue with repairs. Lets focus validation on orion

The accepted improvements preserve quoted external evidence, disable only
Romozinha webhook tools, and retain operator Discord/Telegram workflows, YOLO,
approvals and allowlists. Discovery remains the deployment target; Orion is the
validation host. Argus lifecycle handling belongs to the separate runtime slice.

Q-GUARD-TRUNC-BOUNDARY was explicitly resolved:

> Fail closed (Recommended)

Unfinished raw tool XML owns the rest of the message. Closed evidence before it,
after complete envelopes, or wholly enclosing a structure remains byte-faithful.
The contradictory following-line preservation assertion changed under this answer,
not to conceal failure. Quoted evidence is intentional context, not a secret filter.

## Changes and observed evidence

RTK modifies only successful, changed terminal commands through native directives,
without command logging. Guard classification separates structured syntax quotes
from literal evidence. Romozinha renders healthcheck enabled and webhook `[]`;
baseline comparisons preserve other operator settings.

Pre-R5 validation exited zero: three derivations **built on Orion**, port 2222,
local jobs zero. Stdlib guard/RTK, real-Restic encryption/contract and installed
Hermes v0.21.7/`71d34bad1045610252eda02ee79549436896e784` SDK/PluginManager/native
finalizer passed with synthetic state, superseding the cached-output assumption.
Canonical receipt:
`/home/erik/.local/share/opencode-v2/tmp/opencode/hermes-orion-final-4w9h0jn5/receipt.json`.

Earlier local native RTK old/new-hook fixtures remain separate evidence; this
Orion RTK check is stdlib-only, not native SDK RTK. Native guard validation is not
gateway E2E. Fresh native wiring review `ses_ec42cce03ffeSY164W49oEAz17` is READY,
without blockers; operational daemon sandbox behavior remains unverified.

Latest R5 group exited 124 at its 600-second dependency-rebuild deadline, after
fresh Orion stdlib and real-Restic backup PASS. Native check did not finish again;
its unchanged `y3qsipc118zm6y62zx981krlxv6kzgjc-hermes-plugin-native.drv`
retains the earlier installed-SDK proof (`recovery-r5-orion-receipt.json`).

Pinned-source inspection at `agent_init:1116` and `turnToolValidation:83` confirms
an empty valid-tool set rejects ordinary webhook tool names before execution,
not merely their advertised schemas. Internal kanban-worker dispatch is separate
context; this does not establish a blanket restriction across all workers.

## Grouped discovery and repair receipts

Initial plugin/configuration and callback assertions observed RED.
`hermes-hardening-receipts/` and `agent-validation-20261014/` preserve structured,
delimiter and Markdown repairs. XML candidate 1 covered comment/CDATA/PI/attributes,
then failed backslash review. Candidate 2 passed 3,072 checks before the multiline
conflict. Approved candidate 3 observed control/callback RED, source GREEN and 117
fresh review probes PASS. `RV-guard-xml-*-red.json` / `*-green.json` retain hashes
and decisions. Three-candidate XML budget exhausted; no automatic repairs.

The bounded-extension wording remains preserved:

> One bounded root-fix candidate extension, notnewrepairloop:

> Nextboundedcandidate2 underuser'continuewithrepairs' withinreopenedmax3family;

## Remaining work and recovery

Earlier toplevel `1qrfd6nd2ra8dfs5dg87js7ycrjxilgv…drv` built on Orion after
1,200-second infrastructure timeout and one 600-second continuation. Receipt records
dry-run/lint/format PASS. Latest source dry-run plans fourteen derivations; that
closure is not built. Deployment override forwarding is in progress, not validated;
preview retains local fallback. No activation/drift preview occurred.

**“One scoped attempt”** was consumed: attempt 2 failed in 353.237 seconds, exit 1,
on 2026-10-15. Marker:
`BLOCKED hermes-state-backup {"class": "ValueError", "phase": "remote-unobserved"}`.
Canonical `hermes-scoped-backup-attempt2-vz14doea/receipt.json` records failure;
snapshot/restore and historical recovery remain unconfirmed, cause unknown.
Its `post-failure-unit-state.json` records GET exit 0, zero unit actions:
`docker-hermes-argus.service` and `docker-hermes-agent.service` loaded/active/running;
`hermes-argus-healthcheck.timer` loaded/active/waiting;
`hermes-agent-healthcheck.timer` not-found/inactive/dead, undeployed; no start needed.
This proves current availability only, not before/after equality or image version.
Backup gate explicitly superseded by `rollout-backup-waiver.json` in that directory.
No further backup/preflight/rehearsal/restore/deletions; retain helpers/tests/history
without automatic deployment invocation. No snapshot removed. Task base is not
deployed-baseline evidence; synthetic proof is not live protection.

Exact pre-rewrite content, hashes and grouped history remain privately preserved in
`/home/erik/.local/share/opencode-v2/tmp/opencode/hermes-doc-rewrite-2jp18pbk/`.
Accepted editorial review `ses_ec05c7a39ffeIf2Qke7Re0dQOF` informed refinement;
later drafts: `hermes-doc-editorial-j58093zo/`, `hermes-doc-unit-state-izbdi86t/`.
Operational gate explicitly waived; implementation unchanged.
