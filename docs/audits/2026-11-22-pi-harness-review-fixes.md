# Pi harness review fixes

**Status:** Implemented on `feat/pi-shadow-20261122`, not deployed.

**Scope:** the three defects from the first real read-only run of the durable
harness in `modules/dev/pi-harness`, plus two follow-ups the same review named
(sandbox lifetime, USAGE text), and the defects a fresh whole-slice review
found in the first fix commit.

**Worktree:** `desktop-nixos/worktrees/pi-shadow-20261122` (existing worktree;
`e44fbba6` was not reverted and `worktrees/pi-durable-20261122` was not touched).
The durable type declarations under
`node_modules/@earendil-works/pi-durable/dist/*.d.ts` were the API reference.

## Finding, verdict, fix, test

| # | Review finding | Verdict | Fix | Test |
| --- | --- | --- | --- | --- |
| 1 | `findEntry()` searches the newest 200 entries, so an older answer is missed and a duplicate id in the window picks the wrong one. | Confirmed. The review's suggested query exists. | `Conversation.entries()` accepts `minEntryId` and `maxEntryId` (`dist/types.d.ts`, `EntryQuery`). `findEntry()` now asks for exactly the settled answer id with limit 1 and reads `items[0]`. The 200-entry window remains only for `latestAssistant()` in `resume`. | `test/cli.test.ts` submits an answer, appends 205 passive entries, asserts the answer is absent from the recent window, and asserts `findEntry()` still returns it with its text. |
| 2 | Failure reporting can name a stale run: on `status !== "done"` it prints `live.runFailure` without checking ownership. | Confirmed. `RunFailure.inputs` is `SubmissionId[]` (`dist/harness/live.d.ts`), and the settled record carries `reason`/`detail`. | `describeRunFailure()` reports `settled.reason` and `settled.detail` first. The live failure is a fallback, and only when `runFailure.inputs` contains `settled.id`. | `test/cli.test.ts` runs a faux conversation with `maxTurns: 1`, receives `status: "unanswered"`, `reason: "turn_limit"`, `detail: "1 turn"`, and asserts the report is exactly `turn_limit: 1 turn`. A synthetic settled record with an empty reason then asserts the live fallback: inputs containing its id yield `aborted`; other inputs yield the empty settled reason. |
| 3 | `status` prints the first 100 conversations as a total. | Confirmed: `scanConversations()` returns `Page.next`. | `scanConversationPages()` follows `next` up to 10 pages of 100. It reports `truncated: true` when a next page exists at the bound. `commandStatus()` prints `conversations: N` or `conversations: at least N (more pages)` from the same `items` array it iterates. USAGE states the 1000-conversation bound. | `test/cli.test.ts` follows a two-page fake scan and asserts both rows; a second fake always returns `next` and asserts two pages, two rows and `truncated: true`. Seeding 1000 real conversations was rejected as slow; the bound is stated in USAGE and here. |
| 4 | `CodemodeSandbox` is built inline, so `OpenedHarness.close()` cannot close it and a CLI exit during a script leaves the worker. | Confirmed. `CodemodeSandboxBase.close()` exists and "aborts in-flight executions" (`pi-codemode/dist/runtime/execution.d.ts`). | `openHarness()` keeps the sandbox handle and closes it after the harness. Close errors are ignored. The open-failure path also closes it. | `test/cli.test.ts` spies on `CodemodeSandbox.prototype.close`, opens and closes a harness, and asserts one call. |
| 5 | USAGE claims model/thinking defaults that only apply on first creation. | Confirmed for USAGE; README already states persistence. | USAGE now says "default on first creation: …" and "the stored model wins on reopen unless this flag is passed" for both flags. Behavior is unchanged. | No test: text-only change. README's existing paragraph (`--model` and `--thinking` change a stored conversation only when passed) was re-read and left as is. |

## Rejected alternatives

- **Fail loudly when the id is outside the window.** Rejected: the bounded
  exact query exists, so the loud-failure branch is unnecessary. A genuinely
  missing id still prints `(no assistant text)`, as before.
- **Unbounded `status` paging.** Rejected: the review prefers a bound. Ten pages
  is one constant; the printed line marks truncation.
- **Change `--model`/`--thinking` to always apply.** Rejected: the task forbids a
  behavior change, and the stored-agent rule is deliberate (documented in the
  durable slice one-pager, decision 8).
- **Report the live failure whenever it matches this submission.** Rejected:
  the task asks for the settled reason first. The live record is used only when
  the settled reason is empty.

## Review round on the first fix commit

A fresh pilot-l3 review accepted the first commit with nits and found four
substantive gaps. All were fixed and the tests now prove the intended path:

1. **Symlinked entrypoint regression.** `import.meta.url` resolves to the real
   file, so comparing it to `argv[1]` made a symlinked `bin` silently do
   nothing. `isEntrypoint()` now compares against `realpathSync(argv[1])`.
   Verified by running `node` on a symlink to the emitted `dist/cli.js`: it
   prints USAGE.
2. **Vacuous stale-failure assertion.** The `turn_limit` record has a reason, so
   the ownership check was never evaluated. A synthetic settled record with an
   empty reason now asserts both sides: matching inputs use the live reason,
   other inputs return the empty settled reason.
3. **Entry test did not prove the query.** It only showed the window was too
   small. The test now spies on `root.entries()` and asserts the exact call:
   `{ minEntryId, maxEntryId }` for the settled id and limit 1.
4. **Sandbox close was not guaranteed.** It followed two unguarded awaits. The
   harness close is now inside `try`, with `sandbox.close()` in `finally`.
5. **No test for the count line.** `describeConversationCount()` is extracted
   and tested for both the exact and truncated forms.
6. **USAGE wording.** It now says the stored value wins unless the flag is
   passed, matching README.

Test count after this round: 20.

## hackerman-cr rounds

- At `c3e396bf` the bot raised two P2 documentation defects: the durable
  one-pager still claimed the harness was unwired, and the shadow audit recorded
  `pi` commands that now start the harness. Fixed in `37dbd49d`; the catalogue
  and package-pin checks were re-run as `pi-agent` with the same output.
- At `37dbd49d` it raised one P2: the new suites had no CI gate. `_tests.nix`
  now exposes `checks.pi-harness-tests`, which runs `vitest` inside
  `buildNpmPackage`, and `check.yml` builds that check and runs
  `modules/dev/pi-extensions/rtk.test.js`. The Nix log reports 7 files and 20
  tests.
- At `a136b409` it raised one P2: the check skipped `tsc`, so a type error that
  breaks the installed artefact would pass. The check now runs `npm run build`
  before `npm test`.

## RED evidence

The tests were written against helpers holding the old behavior first. Five
assertion failures, one per fixed path:

```
× cli entry lookup > finds an answer older than the recent-entry window
  → expected undefined to be 11
× cli failure reporting > names the settled turn_limit, not a stale live failure
  → expected 'aborted' to be 'turn_limit: 1 turn'
× cli status scan > follows pages and counts every printed row
  → expected [ 1 ] to deeply equal [ 1, 2 ]
× cli status scan > stops at the page bound and says it is truncated
  → expected [ { id: 1 } ] to have a length of 2 but got 1
× harness close > closes the code-mode sandbox with the harness
  → expected "close" to be called 1 times, but got 0 times
```

## GREEN evidence

```
$ ./node_modules/.bin/tsc -p tsconfig.json --noEmit
tsc exit=0

$ ./node_modules/.bin/vitest run
 Test Files  7 passed (7)
      Tests  20 passed (20)
```

Before: 6 files, 13 tests. After: 7 files, 20 tests.

Two premises were probed before the fix, with a throwaway test since deleted:
a `maxTurns: 1` faux run settles `unanswered` with `reason: "turn_limit"`,
`detail: "1 turn"`; and `entries({minEntryId, maxEntryId}, 1, …)` returns the
answer after 205 filler entries while the descending 200-entry window does not
contain it.

## Gates

```
$ nix build .#pi-harness --no-link --print-out-paths
/nix/store/m2zqglcfksvs93d80wdw5g601kjngb1d-pi-harness-0.1.0

$ just lint          # exit 0 (statix)
$ just fmt-check     # exit 0 (alejandra, 245 files)
```

The built binary was run to prove the new `main()` guard still starts the CLI
under the Nix wrapper, and that `status` prints one conversation for one row.
A `node` run on a symlink to the emitted `dist/cli.js` also printed USAGE,
which is the regression the first fix commit introduced:

```
$ pi-harness status --project "$project" --state-dir "$state" --no-mcp
conversations: 1
  1
live tasks: 0
usage: none
```

No live model request ran. The optional mini smoke was skipped; the fixes are
covered by faux-provider tests and the CLI start above.

## Command wiring

`modules/dev/pi.nix` now installs the durable harness as both `pi-harness` and
`pi`. The upstream shadow agent is exposed as `pi-agent`, so the profile has no
`bin/pi` collision and the `~/.pi/agent` configuration still belongs to that
agent. The harness entrypoint guard resolves symlinked `argv[1]`, which is what
makes the `pi` symlink invoke `main()`.

## Changed files

- `modules/dev/pi-harness/src/cli.ts` — exact-id lookup, settled failure report,
  bounded status pages, entrypoint guard, USAGE text.
- `modules/dev/pi-harness/src/harness.ts` — keep and close the code-mode
  sandbox.
- `modules/dev/pi-harness/test/cli.test.ts` — new; 7 tests.
- `docs/audits/2026-11-22-pi-harness-review-fixes.md` — new.
- `docs/audits/2026-11-22-pi-durable-slice-one-pager.md` — review-fixes section.

Untouched as required: `e44fbba6`, `modules/dev/pi.nix`, every OpenCode file,
dependencies, the `pi-durable-20261122` worktree. Nothing was pushed.

## Remaining limits

- `status` reports at most 1000 conversations and says so. The count always
  equals the printed rows.
- `findEntry()` returns undefined for an id that does not exist in the root
  conversation; `ask` still prints `(no assistant text)` in that case.
- The live-failure fallback in `describeRunFailure()` is reachable only when a
  settled record carries an empty reason. It exists to satisfy the
  ownership-check requirement, not a known current path.
