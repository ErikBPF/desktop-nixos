# Agent shell policy and MCP health

**Status:** First draft implemented and unit-verified on `main` (96d3376b) in the
worktree `opencode-mcp-shell-permissions-20261120`; RV review pending; not yet
activated on Endeavour.
**Seed (verbatim):** "check why our mcps are breaking and why pilot-l1 agent
still does not have shell access. Base on deskto-nixos main" → then "lets change
pilot l1 to allow and fix deny tail. Also fix mcps. After do a /rv and create
prs".

## Outcome

Two independent defects are fixed in `desktop-nixos`.

1. `pilot-l1` is the only agent whose resolved `shell` effect was `ask`; `pilot-l2`
   and `pilot-l3` inherit the global `shell allow *`. `ask` behaved as `allow`
   only because `ol`/`ow` pass `--auto` and `cli.json` sets
   `session.permissions = "autoaccept"`, so L1 lost shell on any surface without
   auto-accept. L1 now carries `shell allow *` explicitly.
2. The shell deny tail matched the literal text of each subcommand and refused
   ordinary work. The blanket `git show *:*` denied every
   `git show <rev>:<repo-relative-path>` review read, and `*.age*` matched
   `.agents`, so naming the skills directory was refused.

3. `donsetch` was launched through `npx` at backend start; the live homelab
   backend reported it as failed while the Nix-packaged `graphify` and `nix`
   servers connected. `donsetch` is now a Nix derivation from its release
   tarball.

## Changes

- `modules/desktop/workspace-sessions.nix`: `pilot-l1` shell rule `ask` → `allow`;
  the protected deny tail still follows, and `edit` stays denied outside
  `docs/*`.
- `modules/dev/opencode.nix`: `git show *:*` replaced by blob forms narrowed to
  the protected shapes; `*.age*` → `*.age` so `.agents` is admitted; the tail
  comment states that it matches literal subcommand text and is not a content
  boundary. New `donsetch` derivation (`autoPatchelfHook`, `appendRunpaths =
  ["$ORIGIN"]`, `libonnxruntime.so` installed beside the binary) and
  `mcp.donsetch.command = ["${donsetch}/bin/donsetch" "mcp" "--supervised"]`.
- `tests/opencode-profiles/test_settings.py`: the donsetch assertion now expects
  the store path, and the allow list gains the blob review read and `.agents`.
- `tests/opencode-profiles/test_three_level_backends.py`: L1 shell expectation
  `ask` → `allow`.

## Evidence

| Claim | Evidence |
| --- | --- |
| L1 was the only role with `ask` | live `GET /api/agent` on 4097: `pilot-l1` shell `ask`; `pilot-l2`/`pilot-l3` `allow` |
| The tail caused the refusals | every recorded `permission.rejected` replayed from the session database: 27 `git show *:*`, 9 `*.env*`, 6 `*secrets/*`, 5 `*/.ssh/*`, 4 `* -exec *`, 3 `nix eval *`, 2 `*.age*` |
| donsetch failed live | `GET /api/mcp` on 4096: `donsetch {"status":"failed","error":"Request timed out"}`; 4097 connected |
| The package works | derivation built; `readelf -d .../bin/donsetch` shows `RUNPATH ...:$ORIGIN`; an MCP `initialize` on stdin returned `"result"` |
| Tests | `python3 -m unittest discover -s tests/opencode-profiles -p 'test_*.py'` — 18 pass |
| Repository gates | `just fmt-check`, `just lint`, `just structure-check`, `just docs-check` pass |

## Limits and blockers

- Nothing was activated. `just home-switch endeavour` was not run, so the live
  backend still serves the old generation.
- `graphify` still logs `failed to list MCP resource templates: Method not
  found` on every connect; the server implements no resource templates. It is
  noise, not a broken connection.
- `inhire` appears only in old session logs and a dataplatform proposal
  (`docs/proposals/openwebui/inhire-mcp.md`, status "exploration for feedback").
  No repository config declares it, so nothing was removed.
- `desktop-nixos/.mcp.json` is the Claude Code shape and is not read by the
  `ol`/`ow` backends; it was left unchanged.
- Environment faults observed while working, unrelated to this change:
  `http://orion:5000` accepts connections but does not answer, which makes any
  local store operation hang unless `NIX_CONFIG='substituters =
  https://cache.nixos.org'`; and the fleet builder had no free slot because a
  `nix run .#deploy-rs -- .#discovery` job had been running for 3 h 52 m. The
  derivation was verified with a local build
  (`nix-build --option builders '' --option max-jobs 4`).

## Decisions

- Drop the blanket `git show *:*` blob denial. It refused the normal review
  read; the `read` action and the `tool.use` policies remain the boundary.
- Keep the content substring denials. They are defence in depth, and narrowing
  them to path shapes would move the boundary into prose matching.
- Package `donsetch` rather than keeping `npx`: the backends must not resolve a
  tool from the npm registry at start.
- Reject the first draft's `*.env.example*` shell allow. The tail matches one
  subcommand, so a command that names the template next to a real `.env` would
  be admitted; `read` already allows the template, and the deny tail stays the
  single word on the shell text.

## Risks and recovery

- Auto-accept still turns `ask` into approval; the deny tail remains the only
  shell gate for both the desktop and the backends.
- Rollback is the previous generation plus `just home-switch endeavour`. The
  change is additive: no state, database or key is migrated.
- After activation, confirm `GET /api/mcp` on 4096 and 4097 reports `donsetch`
  connected, and that a `pilot-l1` session runs a shell command without a
  prompt.
