---
name: cr
description: Hand current work — a diff, a stage one-pager, or a support document — to a human-led tuicr review, then reconcile the user's comments (fix, answer, or justify). Use when the user says "/cr", "code review handoff", "review my changes", "review this one-pager", "review this doc", "open in tuicr", "run my changes through review", or after finishing a change or a stage page that needs human review before a PR.
---

# /cr — tuicr review handoff

Human-led review of the agent's own work. This is the tuicr skill's workflow 1:
you never self-review the patch or document, never add agent comments to the
session, and never impersonate the user's comments.

## 1. Resolve the target

Pick the target from the user's request; default to the diff.

- **diff** (code change) — the task's uncommitted work or last commit.
- **artifact** (stage one-pager or support document: decision map, `.feature`,
  plan) — the document path or its directory.

Repo = current working directory. Record the reviewed revision and bind the
session to it: the commit/ref for a diff, the file `sha256` (and base commit)
for an artifact.

Commit policy:

- diff: ask whether to commit as part of the handoff. If yes, stage only the
  files that belong to the change and write a Conventional Commits message
  (subject = area + what, body = why + what was verified, no AI attribution).
  Never stage unrelated dirty files.
- artifact: commit only if the user asks. Hand the working-tree document at its
  current revision so the human reviews the exact bytes under discussion.

## 2. Launch the TUI

Build the tuicr args: diff → none (`-w` to force uncommitted-only); artifact →
`--file <path>` (a directory is allowed).

Bridge into the active multiplexer:

| Environment | Action |
|---|---|
| `$CMUX_WORKSPACE_ID` | the tuicr skill's cmux wrapper with pass-through: `<skill-dir>/tuicr-wrapper-cmux.sh <repo> -- <args>`; returns at once — capture the `=== TUICR SURFACE ===` ref |
| `$TMUX` | open a full new window running tuicr: `tmux new-window -c <repo> "tuicr <args>"` |
| `$ZELLIJ` | run `tuicr <args>` in a new pane, reusing the zellij wrapper's pane command |
| `$HERDR_ENV` = 1 | run `tuicr <args>` in a new Herdr pane, reusing the herdr wrapper's pane command |
| none set | tell the user to run `tuicr <args>` in the repo, then wait |

The tmux, zellij and herdr wrappers do not forward extra arguments, so launch
tuicr directly when args are needed. When no extra args are needed you may use
the matching wrapper instead. Use a long (10-minute) timeout for the blocking
wrappers.

## 3. Collect the session and comments

After the TUI exits:

```bash
tuicr review list --repo <path>
tuicr review comments --repo <path> --session <slug>
```

Pick the newest `local` session covering this work (an artifact session slug
contains `~file`); if several are active or none clearly matches, ask the user
for the slug. If you are waiting while the user reviews, poll `review comments`
about every 30 seconds and compare comment IDs; stop when the user says the
review is done.

## 4. Reconcile feedback

Treat each comment by type:

- `issue` — blocking: fix first, then verify.
- `suggestion` — implement or explain why not.
- `note` — answer or acknowledge.
- `praise` — no action.

For fixes: repair at root cause (check every caller, not just the named line),
verify with the repo's own runner, and report evidence. Never weaken acceptance
to make a comment go away.

Record each point's disposition (fixed, declined with reason, answered) in the
stage one-pager or the canonical question ledger, bound to the reviewed artifact
revision. A closed review window is not approval.

## 5. Empty or missing sessions

If comments come back empty after the TUI exits, ask whether the user saved
comments in the intended session or whether another active session should be
read. If `tuicr` is missing or a wrapper fails, say so plainly and fall back to
asking the user to paste their feedback.
