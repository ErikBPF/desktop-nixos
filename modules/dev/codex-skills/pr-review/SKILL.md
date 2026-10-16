---
name: pr-review
description: Review someone else's pull request and produce guidance for the human to post. Use for `/pr-review` or `$pr-review`, or when asked to review a PR, check or answer maintainer feedback on a PR, triage a PR before commenting, or prepare a request-changes or approve decision. Complements rv (our own artifacts) and cr (tuicr handover of our own work).
---

# Upstream PR review

Someone else's pull request, not our own diff. Never post a comment, review, or
label unless the user explicitly authorizes it. Produce guidance and let the user
decide. Answering maintainer feedback already on the PR is part of this workflow.

## 1. The target repo's own skills come first

Before reading the diff, check the target repo and load every review skill whose
area the PR touches:

- `<repo>/AGENTS.md`, `<repo>/.ai/skills/`, `<repo>/.claude/skills/`

More than one usually applies. A schema change that alters serialization is also
a compatibility change. Repo-specific checks stay in the repo. This skill covers
the parts every review needs. Read the repo's own PR expectations and contributor
guide too.

## 2. Gather state, then read prior discussion

Title, body, draft and state, and the changed file list:

```shell
gh pr view <pr> --repo <owner>/<repo> --json title,body,isDraft,state,files
```

Then read every existing review, inline thread, and conversation comment before
forming an opinion:

- `gh pr view <pr> --repo <owner>/<repo> --comments`
- `gh api repos/<owner>/<repo>/pulls/<pr>/reviews`
- `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
- `gh api repos/<owner>/<repo>/issues/<pr>/comments`

Do not duplicate feedback others already gave, and build on existing threads
instead of opening parallel ones. Ignore Copilot and generated summary reviews,
but not bots that report failing checks, advisories, or dependency breaks. If
nothing new remains beyond what is already discussed, say exactly that.

## 3. Read the diff and its neighbours

`gh pr diff <pr> --repo <owner>/<repo>`. Read the surrounding code, not only the
hunks. The most common finding is a change that works but does not match how the
neighbouring code solves the same problem. Cite file and line for every point.

## 4. Compare behavior against the latest release, not only main

Users upgrade from a release, and `main` may already carry unreleased changes in
the same code. Find the release line the repo maintains, then compare:

```shell
git ls-remote --heads <repo-url> 'branch-*' | sort -t- -k2 -V | tail -1
git fetch <repo-url> branch-X.Y:release-X.Y pull/<pr>/head:pr-<pr>
git diff release-X.Y...pr-<pr> -- <changed files>   # only what the PR changed
git diff release-X.Y  pr-<pr> -- <changed files>    # what an upgrading user sees
```

The `branch-*` glob and "highest wins" ordering fit repos that name release lines
that way. Otherwise use the branch the repo designates. The three-dot form
isolates the PR's own changes. The two-dot form answers the upgrade question but
also includes what `main` changed since the release, so attribute each difference
to the PR or to `main` before reporting it.

Per touched path, ask whether any of these differ from the release: the result for
some input (null, empty, NaN, `-0.0`, boundary, timezone), whether a query raises
an error and which, whether the path is enabled by default or falls back, a
default, a config name, a support level, or the speed and memory of an existing
path. A file the release does not have at all is new behavior relative to it, so
say that rather than "no change". The tests the PR adds are a good probe: one that
would fail on the release marks a released behavior change. Classify each
difference as intended (documented, backport considered) or unintended (a
regression). Report the comparison even when nothing changed.

## 5. Evidence rule

Ground every claim in the authoritative source: upstream code, the spec, a
reproduction, a test run. "It looks right" is not a finding. Verify before
raising and drop what you cannot support, per the shared review safeguards.
Reconcile author-reported results against what you ran yourself, and label a
result author-reported when you did not run it.

## 6. Review bar

Every finding is actionable or it is cut. Never label feedback "nit", "minor",
"optional", "low priority", or "feel free to ignore". That tells the author to
skip it and leaves nobody accountable. Bikeshedding is worse than silence, so a
preference needs a correctness, performance, compatibility, or maintainability
argument. Prefer iterating on the PR over merging it and trusting a follow-up,
because a follow-up that is not filed as an issue does not get done. If the work
belongs in separate work, say so plainly and ask for a tracking issue link.

## 7. Review state

Blocking depends on the repository's branch protection, so check it rather than
assuming. Where the protected branch requires approving reviews and the reviewer
has write access, a **Request changes** review blocks the merge until that
reviewer approves or someone with write access dismisses the review. Where the
branch requires conversation resolution, an unresolved inline thread blocks it
too. Where neither rule is in force, no review state blocks the merge by itself.

- **Request changes** for a correctness problem the PR introduces (a different
  result from the reference implementation, a crash, hang, leak, lost or
  corrupted data, a silently overclaimed compatibility) or a performance
  regression on an existing path. A tracking issue does not address either one.
- **Approve**, or dismiss the earlier review, on re-review once the findings
  behind that request-changes review are addressed.
- **Comment** otherwise.

Requesting changes commits the reviewer to the re-review.

## 8. Output

1. PR summary, brief.
2. Which repo and area skills were loaded, and why.
3. CI status from `gh pr checks <pr> --repo <owner>/<repo>`, adding
   `--json name,state,bucket --jq '.[] | select(.bucket != "pass")'` for detail,
   including checks that are blocked or awaiting approval.
4. Behavior comparison against the release, every difference marked intended or
   unintended, or "no change".
5. Findings grouped by area, each with evidence and file and line.
6. Test and documentation coverage: is the changed behavior tested, does CI
   actually run the new test, and does the change need a user-facing or
   contributor doc update that belongs in this PR.
7. Suggested review comments the reviewer could leave, all of them expected to be
   addressed.
8. Recommended review state.

Keep the tone plain and human. Use short separate sentences and no em dashes or
semicolons. Use backticks around code references. Ask about edge cases, suggest
tests, and acknowledge what the PR does well before raising concerns.
