# hermes-flake update hardening

**Status:** Implemented. **Date:** 2026-06-30.
**Audience:** Maintainer of `hermes-flake` and `desktop-nixos`.
**Post-read action:** Implement updater trust hardening first, then widen CI in
the same milestone.

## 1. Context

`hermes-flake` already has an update strategy close to `claude-code-nix`.

It pins upstream `NousResearch/hermes-agent` as a non-flake source input, builds
the package with `uv2nix`, exposes `nix run .#update` and `nix run
.#update-check`, runs an hourly GitHub Actions updater, opens automated PRs,
enables auto-merge, and publishes successful main builds to FlakeHub.

The current strategy is good enough to produce updates. The remaining work is
hardening: make the updater safer, more observable, less branch-message fragile,
and clearer for consumers.

Resolved decisions from review:

- Do both trust hardening and CI widening, but as two ordered slices in one
  milestone.
- Trust hardening lands first: action pinning, non-destructive rollback,
  state-based tagging, release notes in PRs, and consumer trust docs.
- CI widening lands second, after the automation path is safer.
- Updater rollback must preserve pre-existing local edits outside CI.
- Tags are created only from upstream Hermes release tags present in flake
  state, not arbitrary source refs.
- FlakeHub wildcard publishing is gated by required checks on main; advisory
  failures do not block publishing but must be visible in job summaries.
- Action SHA refresh should happen through automated quarterly PRs.

## 2. Goal

Make automated Hermes updates boring:

- update PRs are easy to review;
- CI failures point at package, dependency, config schema, or module breakage;
- auto-merge cannot silently ship a weakly verified release;
- FlakeHub wildcard consumers receive only commits that passed the intended
  checks;
- tags and release notes explain which upstream Hermes release is packaged.

Non-goals:

- Do not redesign Hermes packaging from `uv2nix`.
- Do not replace the upstream release pin with a floating branch.
- Do not move runtime deployment policy out of `desktop-nixos`.

## 3. What is already working

Keep these pieces:

- source pin in `flake.nix`;
- `scripts/update-version.sh` with `--check` and `--version`;
- `apps.update` and `apps.update-check`;
- base package build;
- smoke check;
- module/config checks;
- FlakeHub publish + wildcard verification;
- automated PR flow.

This is already stronger than `codex-flake` because `hermes-flake` owns the
package and the update lane.

## 4. Gaps

### G1 — Moving GitHub Actions refs

Workflows use moving action refs such as `actions/checkout@v6`,
`DeterminateSystems/nix-installer-action@v22`, `nix-community/cache-nix-action@v7`,
`peter-evans/create-pull-request@v8`, and `flakehub-push@main`.

For a repo that auto-merges dependency bumps, action pinning matters. A changed
action can alter the update path without a repository diff.

### G2 — Auto-merge before full confidence

The update workflow runs the update script, creates a PR, then enables
auto-merge. Whether this is safe depends on branch protection and required
checks. The policy should be explicit:

- which checks are required;
- whether best-effort checks can fail;
- whether full extras or VM checks are allowed to be non-blocking.

### G3 — Update script rollback uses git checkout

On build failure the script restores `flake.nix` and `flake.lock` with
`git checkout`. That is acceptable inside clean CI, but risky as a local
developer command because it can clobber unrelated uncommitted edits to those
files.

### G4 — Latest release source is single-path

The script uses GitHub `releases/latest`. If upstream publishes a bad latest
release, yanks a release, or changes release semantics, the updater has little
context. The workflow separately uses `gh api`, so the script and workflow can
disagree on failure mode.

### G5 — Tags depend on merge commit message

Auto-tagging is triggered by a main-branch commit message matching a specific
pattern. Squash merge title changes, manual merges, or create-pull-request
format changes can skip tags even when a real upstream bump landed.

### G6 — Release notes are not captured

Automated PR body says review release notes, but does not include upstream notes
or a link to the exact release. Reviewers must go fetch context.

### G7 — Consumer update semantics are implicit

Consumers can use FlakeHub wildcard, GitHub main, or exact pins. The README
documents usage, but the update trust posture should be as explicit as
`claude-code-nix`: fastest path, balanced path, and highest-assurance path.

## 5. Proposed changes

### P1 — Pin workflow actions by SHA

Replace moving refs with commit SHAs and comments naming the human version.

Minimum set:

- checkout;
- Nix installer;
- cache action;
- create-pull-request;
- FlakeHub push.

Add automated quarterly PRs to refresh action pins.

Use automated quarterly PRs for action-pin refresh. Manual calendar chores are
too easy to miss and pinned actions otherwise silently rot.

### P2 — Split update verification into required and advisory checks

Required for auto-merge:

- `nix flake check --no-build`;
- lint;
- base smoke;
- config schema;
- config override;
- closure-size guard;
- base `hermes-agent` build;
- selected extras build for `voice`, `anthropic`, and `mcp`;
- FlakeHub publish only after those checks pass on main.

Advisory:

- `hermes-agent-full` if known upstream extras are volatile;
- NixOS VM module test if runner support is inconsistent.

Branch protection should require the required set. The update workflow should
only enable auto-merge; GitHub should decide when the PR is mergeable.

FlakeHub publishing should use the same required-check policy on main. Advisory
checks can fail without blocking publish, but the job summary must call that out
so wildcard consumers and maintainers can see the residual risk.

### P3 — Make rollback non-destructive

Change the update script to snapshot original file contents before editing and
restore those exact temp copies on failure. Avoid `git checkout` in a user-facing
script.

Expected behavior:

- if `flake.nix` or `flake.lock` had local edits before the script ran, failed
  update restores those local edits;
- if update succeeds, local edits remain visible in the final diff and the user
  can decide whether they belong.

### P4 — Harden latest-version detection

Use one implementation in the script and workflow:

- prefer GitHub API when `GH_TOKEN` exists;
- fall back to unauthenticated GitHub API with retries;
- parse and validate tag shape `vYYYY.M.DD` or the current upstream convention;
- fail closed if latest tag is empty or malformed;
- print current, latest, release URL, and published timestamp.

Keep `--version` for manual pinning to a known-good release.

### P5 — Tag from flake input diff, not commit message

Replace message-based auto-tagging with a workflow that reads the merged
`hermes-agent-src` input ref from `flake.nix` or `flake.lock`.

Tagging rule:

- if main points at an upstream Hermes release tag such as `v2026.6.19` and the
  matching local tag does not exist, create it;
- if tag exists, do nothing;
- if main points at a branch, commit SHA, or malformed ref, do not create a
  version tag;
- do not require the merge commit title to match a pattern.

This makes tags reflect packaged upstream releases, not process or arbitrary
source pins.

### P6 — Include upstream release notes in update PRs

Add to PR body:

- upstream release URL;
- old pin;
- new pin;
- short release note excerpt or first paragraph;
- checklist of local checks run;
- known review triggers: env/schema changes, extras changes, binary/native deps,
  or container behavior.

Keep excerpts short and link to upstream for full text.

### P7 — Document consumer trust modes

Add a README section:

- **Rolling:** FlakeHub wildcard, fastest, receives every successful main
  publish.
- **Version pin:** exact Git tag or FlakeHub exact version, best default for
  reproducible services.
- **Commit pin:** exact commit, highest assurance when combined with local
  builds and no unreviewed cache.

Also document binary/cache trust if a cache is used.

### P8 — Add updater observability

Emit GitHub job summaries with:

- current pin;
- latest pin;
- release URL;
- update applied yes/no;
- changed files;
- build duration;
- smoke result;
- advisory failures.

This makes failed scheduled runs diagnosable without digging through raw logs.

## 6. Optional improvements

### O1 — Dependency-diff report

For update PRs, generate a short diff of Python dependency lock changes or
resolved package changes. This helps catch dependency churn hidden behind a
single upstream release bump.

### O2 — Canary app check

Run a tiny command through `hermes`, `hermes-agent`, and `hermes-acp` where each
binary supports a safe `--help` or `--version` path. The current smoke check may
already cover part of this; make the intended surface explicit.

### O3 — Scheduled lock refresh separate from upstream bump

Separate two lanes:

- upstream Hermes bump PRs;
- weekly `nixpkgs` and build-input lock refresh PRs.

This keeps failures easier to attribute.

## 7. Recommended priority

Implement as two ordered slices in one milestone.

Slice 1 — Trust hardening:

1. Pin workflow actions by SHA.
2. Make update rollback non-destructive.
3. Tag from flake state instead of commit message.
4. Include release URL/notes in PR body.
5. Document consumer trust modes.

Slice 2 — CI widening:

1. Split required and advisory update checks.
2. Require base build, base smoke, config/schema checks, closure-size guard, and
   selected extras builds for `voice`, `anthropic`, and `mcp`.
3. Keep full extras and VM module tests advisory unless runner support becomes
   reliable enough to make them blocking.
4. Gate FlakeHub wildcard publishing on the required-check policy.

## 8. Implementation slices

1. **Action pins:** replace moving refs with SHAs and version comments; add
   automated quarterly refresh PRs.
2. **Script safety:** snapshot/restore edited files, unify latest detection, add
   release URL output.
3. **PR body:** include release URL, old/new refs, verification, and review
   triggers.
4. **Tagging:** rewrite tag workflow to derive tag from current source pin.
5. **Checks policy:** document required vs advisory checks, align branch
   protection, and gate FlakeHub publishing on required checks.
6. **README trust modes:** add rolling/version/commit pin guidance.
7. **Observability:** add structured job summaries to updater and build
   workflows.

## 9. Acceptance criteria

- Scheduled update PRs can be reviewed without leaving the PR page for basic
  context.
- Failed local updater runs do not erase unrelated local edits.
- Tags are created for real packaged upstream versions regardless of merge
  title.
- Auto-merge is gated only by checks that are intentionally required.
- README tells consumers how to choose rolling, version-pinned, or commit-pinned
  consumption.
- Action pins are refreshed by automated quarterly PRs.
- Advisory check failures are visible in job summaries when they do not block
  publish.
