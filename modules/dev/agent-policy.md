## Repository discovery and worktrees

- Use an explicit repository manifest such as `repos.json` before scanning
  sibling directories.
- A directly targeted checkout is valid, including a linked worktree.
- During sibling or multi-repository discovery, skip `worktrees/`. Group remaining candidates by their absolute `git-common-dir` and prefer the checkout whose absolute `git-dir` equals its `git-common-dir`.
- Manual worktrees live under the repository-local `worktrees/` directory.
  Add that path to `.gitignore` and `.graphifyignore` before creating them.
- Tool-managed and temporary worktrees remain valid. Never move or remove them
  automatically. Inspect dirty state first; when cleanup is requested, use
  `git worktree remove` rather than deleting the directory directly.

## Graphify

- Use Graphify when explicitly requested or when the current repository has a
  `graphify-out/graph.json`; query an existing graph before reading broadly.
- Prefer per-repository queries. Treat merged graphs as discovery-only unless
  cross-repository edges exist.
- Build canonical repository graphs by default. Build a worktree-specific graph
  only when explicitly requested.
- Treat graph output as a cache; verify operational, security, ownership, and
  current-state claims in source.
- Never bypass sensitive-file skips or index `*.secrets.json`, `.env*`,
  Sops/Vault material, certificates, or credentials.
- Fall back to `rg` and source files for unsupported formats.


## Evidence and human feedback

Preserve the human seed verbatim. Ground and challenge it against current
source before refinement throughout `/pl`, `/ip`, and `/rv`. The default flow is
`/pl` for behavior, `/ip` for delivery planning, implementation, then `/rv` for
review and revision; enter at the first applicable step for small or settled work.
Use RFC → ADR → spec only when the user explicitly requests that formal flow.
When requested, prepare the RFC once the work is ready for human feedback,
record accepted decisions in the ADR, and derive the spec from those decisions.
Do not infer this requirement from task size or generic design-gate guidance.
One-pagers and questions remain available without an RFC. Preserve accepted
BDD/TDD contracts, assertion-failing RED anchors, seed-integrity review, and
human-authored lessons. Existing approval remains valid; stage
reports do not create new approval gates. Infrastructure failures are not RED.

Read the repository's `env_config.yaml` when present as environment preferences,
not executable authority. Verify current hosts, commands and identities in the
owning source before use. Missing configuration is a question, not permission
to invent credentials or deploy. Keep secrets out of reports and version control.

After PL, IP, RED, GREEN, E2E, RV, and feedback reconciliation, update a concise
one-pager, including partial or blocked stages. Reuse the repository template;
otherwise use: outcome and why; changes; evidence and limits; decisions needed;
work continuing or waiting; risks and recovery. Target 400–650 words for a
substantial stage, shorter for small changes. Link receipts rather than copying
logs. Group repair attempts; distinguish static checks from observed behavior.

### Handover and question queue

Use the harness's native asynchronous question queue when available; otherwise
ask directly and track pending questions in the current work artifact. Each
handover records question ID, checkout, artifact revision, context, requested
input, recommendation, blocked work, and review session ID when applicable.
Use tuicr for point-by-point diff or document annotations and Neovim for edits
or private credential entry. Follow the installed tuicr skill for supported
launch and comment commands; bind the window to this task, never a fixed file.

Continue independent work and reversible work under explicitly recorded
defaults while answers are pending. Do not continue work whose behavior or
authorization depends on the answer. Saving, closing, silence, and timeouts are
not approval. Read returned annotations, compare their revision to current
artifacts, reconcile stale feedback explicitly, and record the disposition of
each point before resuming dependent work.

For credentials, use the repository's ignored purpose-named secret handoff,
mode 0600, and a Neovim session without swap, backup, persistent undo, history,
or diagnostic logging. Never put secret values in tuicr, prompts, screenshots,
receipts, or chat. Consume only requested keys into the sanctioned store and
remove the handoff after successful transfer; report failures without values.

### Two drafts and delivery

Apply two drafts to substantial PL/IP artifacts and implementations, not only
to final code. Build a bounded complete first draft against the human seed and
accepted behavior. Preserve
its revision, RED/GREEN evidence, failures, and unresolved questions. Request a
fresh independent reviewer to read it as a stranger; no fixed waiting period.

Rewrite like you know the end: state the observed accepted outcome, work
backward through boundaries, interfaces, names and rationale, then remove dead
experiments, temporary glue, duplicated configuration and tangents from final
delivery. Keep discovery receipts. Never backdate tests, fabricate certainty,
or silently rewrite acceptance. Reopen planning when the behavior must change.
PL rewrites its decision map and behavior examples; IP rewrites delivery slices
and verification around that outcome. RV owns the implementation rewrite and
final conformance check. Rerun relevant validation on the rewritten result.

Package useful, green vertical PRs with concrete outcomes, dependencies,
validation and rollback. Preserve the RED anchor inside a PR; do not require a
broken PR to merge. Within one repository, an upper PR targets its predecessor;
across repositories, link dependencies and publish/pin artifacts before consumer
landing. Land leaf-first. Do not force-push to beautify history. Publishing and
deployment each require authorization appropriate to their scope.

### Bounded test loop and knowledge tools

Use existing owner recipes and test runners. Fix one hypothesis at a time,
record the baseline, candidate, command, result, and keep/revert decision.
Never weaken acceptance to improve a score. Restore only the experiment's own
changes. Stop after three repairs of the same failure; report the blocker.
An autonomous campaign additionally needs a mechanical metric, explicit budget
and stop condition, and a named target with allowed actions. Unit/static checks
do not establish E2E success. Existing disposable local E2E can run within task
authorization; deployed/live campaigns require the named authorized target.

Use Graphify as specified above. Cognee retrieval stays disabled unless the
repository documents an authorized dataset selection, readiness, and a
read-only query path. Do not broaden an empty selection or automatically sync,
reset, or delete memory. Fall back to source when retrieval is unqualified.
Use Ponytail to remove unnecessary machinery and Caveman to shorten prose,
without dropping evidence, qualifications, security, or agreed behavior.
