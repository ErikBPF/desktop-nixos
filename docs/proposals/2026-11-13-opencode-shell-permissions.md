# OpenCode shell and PR permissions

**Status:** Proposed. Configuration, tests and documentation are unchanged.

## Human seed and destination

The operator asked on 2026-11-13: "lets check our opencode config and be less
restrictive. Agents should be able to manipulate prs and do shell execution.
Refresh main on desktop-nixos and lets propose fixes".

Destination: a session on the `ol`/`ow` backends runs the shell commands it
needs, including GitHub pull-request create, edit, comment, review and merge,
and git write commands. The policy still blocks secret material, destructive
host actions and out-of-band deployment.

Baseline: `main` was ten commits behind `origin/main` and one commit ahead. The
local commit `f8f7db84` ("fix(opencode): keep workspace backends restarting")
rebased onto `53e4ea77` without conflict and remains unpushed.

## Baseline behaviour

The global settings in `modules/dev/opencode.nix` do four things:

- `read` allows every path and denies `protectedReads`.
- `edit` allows every path, asks for `flake.lock` and denies secret shapes.
- `shell` asks for `*`, allows `inspectionShell`, then denies `shellDenies`.
- `session.permissions = "autoaccept"` in `cli.json` and `--auto` on `ol`/`ow`
  approve every `ask`.

The shell allowlist therefore gates nothing today. The deny tail is the only
gate, and it matches the literal command string.

Observed in the refreshed checkout:

| Command | Result |
|---|---|
| `git show HEAD:flake.nix` | denied by `git show *:*` |
| `git -C <repo> log -1 -p` | allowed, because the prefix patterns only match a command that starts with `git log` |
| `git diff main origin/main -- modules/dev/opencode.nix` | allowed, and prints the full patch |
| `gh pr list` | allowed |
| `cat .env` | denied |

The deny tail blocks some spellings of history and blob reads and permits
others. It is not a content boundary. The reference documentation already states
that shell is not a sandbox
([`opencode-profiles.md`](../reference/opencode-profiles.md)). Commit `c3ddbd93`
("anchor shell deny flags to argument boundaries") records the first correction
of the same class: an over-broad pattern blocked ordinary `git log`.

Pull-request manipulation already works under auto-accept. The practical
restriction is the deny tail, which rejects ordinary review commands, and the
`ask *` rule, which describes a prompt that never appears.

## Proposed change

1. Make the global shell policy explicit. Replace `shell ask *` plus the
   `inspectionShell` allowlist with `shell allow *` in the global `permissions`.
   Keep `shellDenies` as the last rule. Runtime behaviour for the shipped
   clients stays the same, and the configuration now states the effective
   policy. The global surface stops using `inspectionShell`.

2. Remove the patch denials from the global deny tail. The affected patterns are
   the `git diff` and `git log` forms with `-p`, `--patch`, `-U` and `--unified`,
   including the anchored variants. Keep them in a separate `historyDenies` list
   that only the architect subagent appends. Plain `git diff` and `gh pr diff`
   already print patches, so these patterns do not protect content. They only
   reject legitimate history review in the default agent.

3. Keep `git show *:*` in the global deny tail. The blob form can print a
   protected file, and the `*.env*` and `*secrets/*` substring denials do not
   catch `HEAD:.ssh/id_rsa`. Record the `git -C` bypass in the comment instead of
   claiming a boundary.

4. Keep the remaining global denials unchanged: force-push, branch `-D/-f/-m`,
   `rm -rf`, `docker rm` and `docker volume rm`, `nix eval`, `find -exec`,
   `rg --pre`, secret path substrings, and the raw cross-host deploy forms.

5. Keep the architect read-only. It keeps `edit * deny`, `shell * deny`, the
   inspection allowlist and `historyDenies`. Keep the L1 `edit` denial outside
   `docs/*`.

## Non-goals

- No change to the `read` or `edit` denies.
- No change to provider policies.
- No new approval prompt. The change does not re-enable prompts.
- No change to the L1 role boundary.

## Risk and mitigation

- A session that selects `session.permissions = "ask"` will execute shell
  commands without a prompt after this change. The shipped clients already
  auto-approve, and the deny tail still blocks the listed destructive commands.
  The reviewer accepts this trade explicitly, because the operator asked for
  unattended shell execution.
- Removing the patch denials grants no new content access. `read` already allows
  every unprotected path, and plain `git diff` already prints patches.
- The deny tail still matches only literal prefixes. That limitation stays and
  becomes documented.

## Verification

- `python3 tests/opencode-profiles/test_settings.py` passes after the test
  update. The test evaluates the Endeavour Home Manager settings.
- `just docs-check`, `just lint` and `just fmt-check` pass.
- After `just switch endeavour`, an interactive session shows `git log -1 -p`
  and `gh pr view <number>` allowed, and `cat .env` denied. The operator records
  the command output.

## Delivery slices

| Slice | Owner | Scope | Acceptance |
|---|---|---|---|
| S1 | general | `modules/dev/opencode.nix` (global `shell allow *`, `historyDenies`, architect list) and `tests/opencode-profiles/test_settings.py` (allow and deny expectations) | settings test passes; no secret path becomes readable |
| S2 | general | `docs/reference/opencode-profiles.md`: replace the "deny tail is the gate" paragraph with the policy above | `just docs-check` passes |
| S3 | verify | `just switch endeavour`, then the interactive allow and deny checks | recorded output matches the S1 acceptance |

## Open question

Should the L1 role keep its `edit` denial outside `docs/*`? The operator asked
for pull-request manipulation and shell execution, so this proposal keeps the
boundary. Relaxing it would let L1 implement directly and skip the L2 slice.
