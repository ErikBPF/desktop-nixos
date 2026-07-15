# TokenSave on the dataplatform repos — evaluation

**Status:** Evaluated and dropped (2026-07-15) — self-benchmark claimed 95%
savings, but the evaluation failed the adoption contract: no independent A/B
correctness evidence, 81 MCP tool schemas, and stale/branch-drifted indexes.
**Date:** 2026-07-02.
**Audience:** Maintainer of the nstech dataplatform repos + this flake's dev
tooling.
**Post-read action:** None. Reopen only with an independent correctness-controlled
A/B method that addresses §7.

## 1. Context

[TokenSave](https://github.com/aovestdipaperino/tokensave) is a Rust MCP
server that pre-indexes a codebase into a libSQL semantic graph (symbols, call
edges, type hierarchies) and answers structural queries directly, instead of
the agent burning tokens on repeated `grep`/`glob`/file-read/Explore. Upstream
claims **88 % mean retrieval savings** (142.8k → 5.5k tokens over 10 queries on
its own repo).

Two candidate consumers were profiled — large, polyglot, agent-heavy, exactly
the shape TokenSave targets (the dendritic flake itself is **not** — mostly
`.nix` + markdown, so it was ruled out):

| repo | tracked files | size | languages |
|------|---------------|------|-----------|
| `dataplatform-airflow` | 519 | 918 MB | Python, SQL, YAML |
| `dataplatform-spark` | 439 | 687 MB | Python + Scala 218 + Java 137 + SQL |

A sibling tool, [Headroom](https://github.com/headroomlabs-ai/headroom)
(context-compression middleware), was also reviewed and **deferred** — it
overlaps RTK (both intercept + compress; stacking two lossy layers is risky,
given RTK already truncated `sops`/JSON output in prior incidents). Headroom is
a separate RFC if pursued.

## 2. Why this needed care (constraints)

The global `CLAUDE.md` doctrine: minimal MCP set (3–6), prefer skills over MCP,
**no MCP added without explicit user request**, project MCP in the project's
own `.mcp.json`. TokenSave's default installer fights this:

- **`tokensave install --agent claude` is global and invasive** — it writes
  `~/.claude.json`, appends prompt rules to `~/.claude/CLAUDE.md`, installs a
  global `PreToolUse` hook, and auto-allows 80+ tools **fleet-wide**. Rejected.
- It **uploads token counts to a worldwide counter by default** — unacceptable
  on nstech work repos. Disabled (`disable-upload-counter`; opt-out recorded in
  `~/.tokensave/config.toml`).

The user explicitly requested this evaluation, satisfying the opt-in; but scope
is confined to the two repos, gitignored, reversible.

## 3. Delivery mechanism — devenv (the reusable artifact)

Both repos already run **devenv + direnv + justfile** (Python 3.13 via `uv`,
JDK17, Spark). TokenSave is not in nixpkgs, ships a dynamically-linked x86_64
ELF release. Rather than a global `cargo`/`brew` install, it is delivered
**through devenv** — version-pinned, reproducible, auto-on-PATH in the shell,
and it inherits the repo's existing direnv activation. This devenv-delivery
pattern (fetch a prebuilt release binary, `autoPatchelfHook` for NixOS) is the
generalizable takeaway, independent of TokenSave itself.

Enablement is entirely **gitignored / local** — nothing team-facing was
committed. Per repo, added to `.git/info/exclude`:

- `devenv.local.nix` — the derivation below (devenv auto-imports it).
- `.mcp.json` — `{"mcpServers":{"tokensave":{"command":"tokensave","args":["serve"]}}}`.
- `.tokensave/` — the libSQL graph.

```nix
# devenv.local.nix (identical in both repos)
{ pkgs, ... }:
let
  tokensave = pkgs.stdenv.mkDerivation rec {
    pname = "tokensave"; version = "7.0.3";
    src = pkgs.fetchurl {
      url = "https://github.com/aovestdipaperino/tokensave/releases/download/v${version}/tokensave-v${version}-x86_64-linux.tar.gz";
      sha256 = "03qbw6vb5kxxv0da7wrkbrdmx8kqzd7l3cz164iqs3233ib2yp89";
    };
    unpackPhase = "tar xzf $src";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = "install -Dm755 tokensave $out/bin/tokensave";
  };
in { packages = [ tokensave ]; }
```

**Prerequisite:** launch `claude` from inside the devenv shell (direnv handles
this) so `tokensave` resolves on `PATH` for the MCP server.

## 4. As-enabled state (2026-07-02)

Graph built with `tokensave init` (respects `.gitignore` → `.venv` skipped):

| repo | files indexed | nodes | edges | init time | `.tokensave` |
|------|---------------|-------|-------|-----------|--------------|
| airflow | 613 | 14,715 | 26,572 | 1.6 s | 22 MB |
| spark | 228 | 5,076 | 3,811 | 0.53 s | 6.6 MB |

Verified: `tokensave doctor` all-green in both; `tokensave tool search` returns
structured `file:line` symbol hits; upload counter disabled. Global state lives
at `~/.tokensave/{global.db,config.toml}` (per-project + lifetime counters) —
outside the repos, uncommitted.

**Freshness:** no daemon (the file-watcher was removed upstream in v6.1.0 for
runaway resource use). Index self-checks on each MCP call with a 30 s cooldown;
`tokensave sync` for manual incremental. Optional git `post-commit`/
`post-checkout` hooks exist for CLI-only workflows — not installed (they'd be a
tracked `.git/hooks` change; the on-call staleness check covers agent use).

## 5. Benchmark plan

Goal: decide whether TokenSave's retrieval savings are real **on our repos and
our query mix**, net of its own overhead, versus the baseline (grep/glob/read/
Explore). Evaluate later, on a real work session.

### 5.1 Method — A/B on a fixed task set

Pick **8–10 representative tasks** actually done on these repos, e.g.:

1. "Where is the Spark `activity` writer defined and who calls it?"
2. "Trace the DAG that ingests `<dataset>` end-to-end."
3. "Which modules import `structlog` and how is it configured?"
4. "Find every Scala class extending `<base>` and its callers."
5. "What breaks if I change the signature of `<function>`?"
6. A cross-language jump (PySpark → Scala UDF).
7. A dead-code / unused-symbol scan.
8. A "summarize this subpackage" onboarding query.

Run each task **twice in a clean session**:

- **A (baseline):** TokenSave MCP disabled (rename `.mcp.json`), agent uses
  native grep/glob/read/Explore.
- **B (tokensave):** MCP enabled, tools available.

Keep model, prompt, and repo state identical between A and B.

### 5.2 Metrics

- **Primary — input tokens to first correct answer** per task (from the session
  transcript / usage). This is the real cost signal.
- **TokenSave-reported savings:** each MCP response carries
  `tokensave_metrics: before=N after=M`; `tokensave status` shows the
  session + lifetime counter; `tokensave cost` gives a $ view;
  `tokensave monitor` is a live TUI. Treat these as **self-reported** — they
  measure raw-file tokens *avoided*, not the true A/B delta. Cross-check
  against actual session usage; don't quote them as the headline number.
- **Correctness:** did B reach the same (or better) answer? A saving that
  degrades answers is a regression, not a win.
- **Latency / overhead:** wall-clock per task; index staleness stalls.
- **Reproducible self-benchmark:** `tokensave bench` in each repo as a
  low-effort sanity anchor.

### 5.3 What to watch for

- **Staleness lies:** edit a file, then query without `sync` — does the 30 s
  on-call check catch it, or does it answer from a stale graph?
- **Index drift on branch switch:** `dataplatform-*` are active; test a
  `git checkout` of a feature branch then a query (`tokensave sync --doctor`).
- **Tool-schema bloat:** 80+ MCP tools load into context. Measure the fixed
  cost they add to a session *before* any savings.
- **Airflow indexed 613 > 519 tracked** (it pulled in vendored `iceberg-rust/`
  docs); confirm the graph isn't padded with irrelevant vendored trees that
  dilute results.

## 6. Results (2026-07-15)

| repo | TokenSave self-benchmark | Index state | Verdict |
|------|--------------------------|-------------|---------|
| airflow | 310.2k → 6.9k claimed (95%) | fallback after branch/worktree drift; full sync 12d old | drop |
| spark | 140.3k → 5.7k claimed (95%) | full sync 12d old | drop |

The numbers are TokenSave's own estimated avoided-file tokens, not independent
session input-token measurements. `tokensave doctor` also exposed 81 tool
permissions/schemas. The fixed schema cost, stale graph risk, and absence of a
clean correctness-controlled A/B mean the ≥40% adoption criterion was not
proven despite the strong self-reported number.

Backout completed: both project-local MCP configs, local devenv packages,
indexes, and TokenSave-only permissions were removed. Global Claude hooks and
`~/.tokensave` state were also removed. Unrelated worktree changes were left
untouched.

## 7. Decision / exit criteria

**Adopt** (promote from gitignored-local to committed per-repo config, with
team sign-off) if, across the task set:

- median input-token reduction to first correct answer is **≥ 40 %**, **and**
- no correctness regressions, **and**
- staleness/branch handling is trustworthy, **and**
- the 80-tool context cost is comfortably repaid.

**Drop** (remove `devenv.local.nix`, `.mcp.json`, `.tokensave/`, and the
`.git/info/exclude` lines; `tokensave uninstall` if global config was ever
touched) if savings are marginal, answers degrade, or staleness misleads.

Committing to the shared repos is a **separate, team-facing** decision — the
`install --local` variant (writes tracked `.mcp.json` + `.claude/settings.json`
+ `CLAUDE.md`) is the mechanism, not to be run unilaterally.

## 8. Backout

Per repo: `rm devenv.local.nix .mcp.json && rm -rf .tokensave`, drop the three
`.git/info/exclude` lines, `direnv reload`. Global: `rm -rf ~/.tokensave` (only
if abandoning entirely). No tracked files were touched, so backout leaves the
repos exactly as found.
