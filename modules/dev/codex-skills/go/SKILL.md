---
name: go
description: Close the /pl → /ip → /rv flow (and /cr reconciliation) by collecting the stage artifacts, writing the final one-pager, showing the human what will run plus the exact /goal objective, and arming one goal loop after an explicit ok. Use for /go, $go, "close this out", "package the flow", "arm the goal", or when a run ends with a mechanical remainder.
---

# Go

Last gate of `/pl` → `/ip` → implementation → `/rv` → (optional `/cr`). Arm one
`/goal` loop with the artifacts this flow produced, after one explicit
confirmation.

This skill never starts work. If a required stage is missing or a gate is unmet,
name the stage and the gate, then stop.

## 1. Collect

Read the artifacts from disk. Do not trust chat memory. Record each path and its
revision (`sha256`), and mark each missing artifact:

- the verbatim seed and the `.feature` contract;
- the decision map or plan, with the accepted slice and verification commands;
- the implementation change: `git diff --stat` against the branch base, plus the
  commit subjects;
- the RV report: verified fixes, discarded findings, validation commands with
  their results, unresolved risks;
- `/cr` dispositions when a review session ran.

## 2. Write the final one-pager

Use the repository template (`docs/templates/stage-one-pager.md` when it exists).
Fill: outcome and why, changes, evidence and limits, decisions, continuing work,
risks and recovery. Link every receipt path. Keep static checks separate from
observed behavior.

## 3. Draft the goal objective

One paragraph, 4000 characters or fewer. Name three things:

- the end state that is still missing;
- the exact command that proves it;
- the stop condition: repair budget, target host, or scope limit.

List the artifact paths the loop depends on. Keep secrets, credentials,
hostnames and deployment authority out. Do not restate finished work.

## 4. Confirm

Send one message with exactly two parts:

1. **What will run** — the objective, the round and stall limits, and the
   evidence the reviewer will accept as done.
2. **The paragraph** — copy-ready in a fenced block.

Then stop and wait. Treat "ok", "go" or "approved" as confirmation. A
correction, a question, a saved file, silence or a closed window sends you back
to step 2 or 3. Never arm on an assumed answer.

## 5. Arm

After confirmation, use the first path that exists:

1. **Goal tool.** A harness tool that arms a goal in this session. Pass the
   paragraph and the artifact paths.
2. **Client command.** OpenCode 2.2.1 and later parse `/goal` in the TUI and the
   Desktop. The agent cannot type into the client, so print the line and hand it
   over:

       /goal <paragraph>

   Scripted arming through `opencode run --command goal --file <path> ...` is not
   the default. The CLI targeting the live session is unverified, and an
   unverified command can open a second session.
3. **No goal loop.** State that the harness has none, and leave the paragraph in
   the one-pager.

Report the armed objective, its status, and the artifact paths the loop carries.
A met goal is not approval of a deploy.

## 6. After the loop

When the goal completes, pauses or stalls, update the one-pager with the
observed result, the commands that ran and the remaining blocker. Code that the
loop changed still needs `/rv`.
