---
name: pr-review
description: Review someone else's pull request and produce guidance for the human to post. Use when asked to review a PR, check or answer maintainer feedback on a PR, triage a PR before commenting, or prepare a request-changes/approve decision. Complements rv (our own artifacts) and cr (tuicr handover of our own work).
---

# Upstream PR review

Someone else's pull request, not our own diff. Never post a comment, review, or
label unless the user explicitly authorizes it: produce guidance and let the user
decide. Answering maintainer feedback already on the PR is part of this workflow.

## 1. The target repo's own skills come first

Before reading the diff, check the target repo and load every review skill whose
area the PR touches:

- `<repo>/AGENTS.md`, `<repo>/.ai/skills/`, `<repo>/.claude/skills/`

More than one usually applies: a shuffle change that touches spilling is also a
memory change. Repo-specific checks stay in the repo; this skill covers the parts
every review needs. Read the repo's own PR expectations and contributor guide.

## 2. Gather state, then read prior discussion

Fetch title, body, draft/state, and changed files, then read every existing
review, inline thread, and conversation comment before forming an opinion.

- `gh pr view <pr> --repo <owner>/<repo> --comments`
- `gh api repos/<owner>/<repo>/pulls/<pr>/reviews`
- `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
- `gh api repos/<owner>/<repo>/issues/<pr>/comments`

Do not duplicate feedback others already gave, build on existing threads instead
of opening parallel ones, and ignore bot reviewers (Copilot and friends). If
nothing new remains beyond what is already discussed, say exactly that.

## 3. Read the diff and its neighbours

`gh pr diff <pr> --repo <owner>/<repo>`. Read the surrounding code, not only the
hunks: the most common finding is a change that works but does not match how the
neighbouring code solves the same problem. Cite file and line for every point.

## 4. Compare behavior against the latest release, not only main

Users upgrade from a release, and `main` may already carry unreleased changes in
the same code. When the repo has release branches:

```shell
git ls-remote --heads <repo-url> 'branch-*' | sort -t- -k2 -V | tail -1
git fetch <repo-url> branch-X.Y:release-X.Y pull/<pr>/head:pr-<pr>
git diff release-X.Y pr-<pr> -- <changed files>
```

Per touched path, ask whether any of these differ from the release: the result for
some input (null, empty, NaN, `-0.0`, boundary, timezone), whether a query raises
an error and which, whether the path runs natively or falls back, a default, a
config name, a support level, or the speed and memory of an existing path. The
tests the PR adds are a good probe: one that would fail on the release marks a
released behavior change. Classify each difference as intended (documented,
backport considered) or unintended (a regression). Report the comparison even
when nothing changed, so the reader knows it was done.

## 5. Evidence rule

Ground every claim in the authoritative source: upstream code, the spec, a
reproduction, a test run. "It looks right" is not a finding. Verify before
raising, drop what you cannot support, and distinguish a static check from
observed behavior from an untested claim. Reconcile author-reported results
against what you ran, and label them as author-reported when you did not.

## 6. Review bar

Every finding is actionable or it is cut. Never label feedback "nit", "minor",
"optional", "low priority", or "feel free to ignore": that tells the author to
skip it and leaves nobody accountable. Bikeshedding is worse than silence, so a
preference needs a correctness, performance, compatibility, or maintainability
argument. If the work belongs in separate work, say so plainly and ask for a
tracking issue link rather than leaving a floating remark.

## 7. Review state

- **Request changes** only for a correctness problem the PR introduces (a
  different result from the reference implementation, a crash, hang, leak, lost
  or corrupted data, a silently overclaimed compatibility) or a performance
  regression on an existing path. A tracking issue does not address either one.
  A comment review does not block a merge; a request-changes review does.
- **Approve**, or dismiss the earlier review, on re-review once the findings
  behind that request-changes review are addressed.
- **Comment** otherwise.

Requesting changes commits the reviewer to the re-review.

## 8. Output

1. PR summary, brief.
2. Which repo and area skills were loaded, and why.
3. CI status, including checks that are blocked or awaiting approval.
4. Behavior comparison against the release, every difference marked intended or
   unintended, or "no change".
5. Findings grouped by area, each with evidence and file/line.
6. Suggested review comments the reviewer could leave, all of them expected to be
   addressed.
7. Recommended review state.

Keep the tone plain and human: short separate sentences, no em dashes, no
semicolons. Use backticks around code references. Ask about edge cases, suggest
tests, acknowledge what the PR does well before raising concerns.
