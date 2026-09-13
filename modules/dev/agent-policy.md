## Repository discovery and worktrees

- Before scanning siblings, read an explicit manifest such as `repos.json`.
- Directly targeted checkouts, including linked worktrees, are valid. For sibling/multi-repo discovery, skip `worktrees/`, group by absolute `git-common-dir`, and prefer checkouts whose absolute `git-dir` equals it.
- Create manual worktrees under repo-local `worktrees/`; first add it to `.gitignore` and `.graphifyignore`.
- Never automatically move/remove tool-managed or temporary worktrees. Inspect dirty state before requested cleanup; use `git worktree remove`, not directory deletion.

## Knowledge tools

- Use Graphify when requested or `graphify-out/graph.json` exists; query existing graphs before broad reads. Prefer per-repo queries; merged graphs are discovery-only unless cross-repo edges exist.
- Build canonical graphs by default; worktree graphs only on request. Graphs are caches: verify operational, security, ownership, and current-state claims in source. Use `rg`/source for unsupported formats.
- Never bypass sensitive-file skips or index `*.secrets.json`, `.env*`, Sops/Vault material, certificates, or credentials.
- Keep Cognee retrieval disabled unless the repo documents authorized dataset selection, readiness, and a read-only query path. Never broaden empty selections or automatically sync/reset/delete memory. Fall back to source when unqualified.

## Evidence and feedback

Preserve the human seed verbatim; ground and challenge it against current source before refinement throughout `/pl`, `/ip`, and `/rv`. Default: `/pl` behavior → `/ip` delivery plan → implementation → `/rv` review/revision. Small or settled work enters at the first applicable step.

RFC → ADR → spec applies only when explicitly requested, never inferred from task size or generic design gates. Prepare the RFC when ready for human feedback, record accepted decisions in the ADR, then derive the spec. Questions and one-pagers need no RFC. Preserve accepted BDD/TDD contracts, assertion-failing RED anchors, seed-integrity review, and human-authored lessons. Infrastructure failure is not RED. Existing approval persists; stage reports add no gates.

Read `env_config.yaml` as preferences, not executable authority. Verify hosts, commands, and identities in owning source. Missing config prompts a question, never invented credentials or deployment permission. Keep secrets out of reports and version control.

After PL, IP, RED, GREEN, E2E, RV, and feedback reconciliation—even partial/blocked—update a one-pager. Use the repo template or: outcome/why; changes; evidence/limits; decisions; continuing/waiting work; risks/recovery. Target 400–650 words for substantial stages, shorter for small changes. Link receipts, group repair attempts, distinguish static checks from observed behavior.

### Handover

Use native async questions when available; otherwise ask directly and track pending questions in the work artifact. Record question ID, checkout, artifact revision, context, requested input, recommendation, blocked work, and applicable review session ID. Use tuicr for point annotations on diffs/docs; Neovim for edits/private credential entry. Follow the installed tuicr skill's launch/comment commands; bind windows to the current task, never a fixed file.

While waiting, continue independent work and reversible work under explicitly recorded defaults; stop work dependent on the answer's behavior or authorization. Saving, closing, silence, and timeouts are not approval. Read annotations, compare revisions, explicitly reconcile stale feedback, and record each point's disposition before dependent work resumes.

Credentials: use the repo's ignored, purpose-named handoff at mode 0600. Neovim must disable swap, backup, persistent undo, history, and diagnostic logging. Never expose values in tuicr, prompts, screenshots, receipts, or chat. Transfer only requested keys to the sanctioned store; remove the handoff after success. Report failures without values.

### Two drafts and delivery

Apply two drafts to substantial PL/IP artifacts and implementations. Complete a bounded first draft against the human seed and accepted behavior; preserve revision, RED/GREEN evidence, failures, and unresolved questions. Have a fresh independent reviewer read it as a stranger; no fixed delay.

Rewrite like you know the end: state the observed accepted outcome; work backward through boundaries, interfaces, names, and rationale. Remove dead experiments, temporary glue, duplicate configuration, and tangents from delivery; keep discovery receipts. Never backdate tests, fabricate certainty, or silently rewrite acceptance. Behavior changes reopen planning. PL rewrites its decision map/examples; IP rewrites delivery slices/verification; RV owns implementation rewrite and final conformance. Rerun relevant validation.

Package useful green vertical PRs with outcomes, dependencies, validation, and rollback. Keep RED anchors inside PRs; never require merging a broken PR. Same-repo upper PRs target predecessors; cross-repo consumers require linked dependencies and published/pinned artifacts before landing. Land leaf-first. Never force-push for prettier history. Publishing and deployment each require scope-appropriate authorization.

### Bounded test loop

Use owner recipes/runners. Fix one hypothesis at a time; record baseline, candidate, command, result, and keep/revert decision. Never weaken acceptance for a better score; restore only the experiment's changes. Stop after three repairs of the same failure and report the blocker.

Autonomous campaigns additionally require a mechanical metric, explicit budget/stop condition, and named target with allowed actions. Unit/static checks do not prove E2E. Existing disposable local E2E may run within task authorization; live/deployed campaigns require a named authorized target.

Use Ponytail to remove unnecessary machinery and Caveman to shorten prose without losing evidence, qualifications, security, or agreed behavior.
