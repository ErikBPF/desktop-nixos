# Implementation plan — Argus alert dedupe

Status: plan; no code written. Human seed and `behavior.md` accepted.
Every slice is vertical: it ships its own grading. Land leaf-first:
Slice 5 (homelab-gitops) is independent; Slices 0-4 are desktop-nixos.

## Ownership and seams

| Artifact | Owner repo | Purpose |
|---|---|---|
| `modules/hosts/discovery/hermes-plugins/alert-dedupe/{plugin.yaml,__init__.py,selftest.py}` | desktop-nixos | Plugin + logic + stdlib self-check |
| `modules/hosts/discovery/hermes-agents.nix` | desktop-nixos | Mount, `plugins.enabled`, ledger env, health check |
| `modules/hosts/discovery/argus-SOUL.md` | desktop-nixos | Trust the marker; drop prompt-only dedupe claim |
| `tests/argus-security/test_argus.py` | desktop-nixos | Config contract |
| `platform/monitoring/files/alerting/templates.yaml` | homelab-gitops | Stable `key` token, unit label, instance count |
| `tests/hermes-agent-runtime.py` | desktop-nixos | Existing disposable-container probe pattern (reused, not modified) |

Test seam: **one** seam. `selftest.py` imports `__init__.py` by path and passes a
fake `ctx` with `register_hook`, exactly as
`toolcall-leak-guard/selftest.py:11-17` does. No Hermes import, no container, no
network. `tests/argus-security/test_argus.py` grades the Nix config textually.
Native behavior is proven once per image change with the existing fixture
pattern (`tests/hermes-agent-runtime.py:172-185`), not per slice.

## Slice 0 — capability probe — **resolved by source inspection (2026-10-26)**

`pre_llm_call` exists, receives `user_message` + `session_id` + `turn_id`, and
injects returned context into the user message; `transform_llm_output` receives
`session_id`/`turn_id` and returns replacement text. Both are used, so no probe
container is needed. The step below is historical.

**Observable result:** a printed inventory of the plugin hook registry and the
kwargs each outbound hook receives, for the pinned Argus image.

- ~~RED: `python3 tests/argus-dedupe-probe.py` exits non-zero~~ — not needed.
- GREEN: new `tests/argus-dedupe-probe.py` following the existing fixture shape:
  `docker run --rm --network none --read-only --tmpfs /tmp -e HOME=/tmp/known
  -e HERMES_HOME=/tmp/known --entrypoint /opt/hermes/.venv/bin/python <pinned
  digest> -c '<walk hermes_cli.plugins for hook names, then print the call-site
  signature for each outbound hook>'`. Digest from `hermes-agents.nix:183`.
- Verification: `python3 tests/argus-dedupe-probe.py`
  Success marker: `PASS argus-dedupe-probe` (printed only when at least one hook
  name and its kwargs are reported).
- Decides: Layer O alone (no context) → **stop and take the D1 fallback**;
  Layer O with context kwargs → variant O; pre-dispatch hook present →
  variants O+I.
- Owner: desktop-nixos. Rollback: delete the file.
- Risks: image not present locally (`--pull=never` semantics); no network by
  design. Infrastructure failure is not RED.

## Slice 1 — pure classification and ledger (no wiring)

**Observable result:** given fixture Discord texts and a fixture ledger, the
classifier returns NEW / REPEAT(n) / NEW_EPISODE(n) / RESOLVED / UNKNOWN with the
marker text.

- RED: add scenarios to `selftest.py` for repeat, new episode, resolved, missing
  ledger, corrupt ledger, grouped message, forged key; run
  `python3 modules/hosts/discovery/hermes-plugins/alert-dedupe/selftest.py` →
  `ImportError: alert-dedupe`. (Assertion-failing RED, not infrastructure.)
- GREEN: `__init__.py` with `parse_message(text) -> list[Instance]`,
  `Family`/`Episode` dataclasses, `classify(instances, ledger, now) -> Verdict`,
  `Ledger.load/save` (atomic tmp+rename, caps: 5 episodes/family, 2000 families,
  30 days), `marker(verdict)`. Parsing prefers the `· key <family> @ <unix>`
  token; falls back to the current prose shape (`templates.yaml:18-27`) and marks
  the verdict approximate. Sanitize token fields to `[A-Za-z0-9._:/-]{1,64}`.
- Verification: same command; success marker `PASS alert-dedupe-selftest`.
- Owner: desktop-nixos. Depends on nothing. Rollback: revert files.

## Slice 2 — output layer wired (deterministic floor)

**Observable result:** with the plugin enabled, a repeat turn's reply begins with
the marker; a new alert's reply is unchanged.

- RED: `tests/argus-security/test_argus.py` gains assertions that
  `plugins.enabled` contains `alert-dedupe`, the mount is `:ro`, and
  `ALERT_DEDUPE_MODE` exists → fails against current config.
- GREEN: `plugin.yaml` (`provides_hooks: [transform_llm_output, <input hook if
  probed>]`), `register(ctx)` wired like
  `toolcall-leak-guard/__init__.py:339-340`; `hermes-agents.nix` gains the
  read-only mount next to `:202`, `"alert-dedupe"` in `:228`, and
  `ALERT_DEDUPE_MODE` / `ALERT_DEDUPE_LEDGER` in `extraEnvironment`.
  Any exception → `return None` (never `NO_REPLY`).
- Verification: `python3 tests/argus-security/test_argus.py && echo PASS
  argus-security-contract`, then `nix flake check --no-build` and
  `just dry discovery`.
- Owner: desktop-nixos. Depends on Slice 0 + 1. Rollback: remove the
  `plugins.enabled` entry and mount, redeploy; ledger file is inert.

## Slice 3 — input layer (only if Slice 0 found a pre-dispatch hook)

**Observable result:** a repeat turn is told, in-prompt, the family, count, and
prior thread, so it answers in one line without re-deriving the incident.

- RED: a selftest case asserting the note is produced for a repeat and absent for
  a new alert; current code has no such function.
- GREEN: `note(verdict) -> str` plus registration on the probed hook, bounded to
  one line, marker fields only.
- Verification: `PASS alert-dedupe-selftest` plus
  `PASS argus-dedupe-input-layer` printed only when the note is observed reaching
  a prompt (single live probe, no inference budget spent on a model call —
  a rendered-prompt assertion suffices).
- Rollback: disable the hook registration via `ALERT_DEDUPE_MODE=output`.

## Slice 4 — resolved handling and health check

**Observable result:** a resolved notification produces a one-line resolved
reply and closes the ledger episode; the health check fails if the plugin is not
registered or the ledger path is not writable.

- RED: extend the health-check fixture assertion in
  `tests/argus-security/test_argus.py` (health check currently asserts nothing
  about plugins, `hermes-agents.nix:290-301`); it fails before the edit.
- GREEN: health check gains `plugins.has_hook("transform_llm_output")`, the
  enabled-name check, and an atomic write+unlink in the ledger directory. SOUL
  gains the resolved rule and drops the prompt-only dedupe claim
  (`argus-SOUL.md:18-24`), replacing it with "the ledger marker is authoritative;
  if it says `ledger unavailable`, say likely repeat".
- Verification: `PASS argus-security-contract` and, on a disposable container
  only, `PASS alert-dedupe-healthcheck`.
- Rollback: revert the health-check block; the plugin stays optional.

## Slice 5 — Grafana template key token (leaf, independent)

**Observable result:** each Grafana Discord alert line ends with a stable
`· key <family> @ <unix>` token; the unit label and a total-instance count are
visible.

- RED: a fixture render (or a grep-based contract in homelab-gitops) fails
  because the token is absent.
- GREEN: `templates.yaml` alert template gains the token and
  `{{ with .Labels.name }}`; the omission line gains `{{ len .Alerts.Firing }}`
  totals. No contactpoint, route, or interval change.
- Verification: render the template with a synthetic payload in the monitoring
  stack's own test path and assert the token for two families;
  `PASS alert-template-key-token`.
- Rollback: revert one file; Argus falls back to prose parsing automatically.
- Note: warning repeats are already 12h (homelab-gitops #197). Do **not** change
  intervals in this slice.

## Slice 6 — measurement (7 days, read-only)

**Observable result:** a printed rate of repeat-marked replies and the ledger
count distribution.

- Metric command (mechanical, no model calls):
  `docker exec hermes-argus python3 -c '<read ledger, print repeats/total>'`
  Success marker: `PASS alert-dedupe-measure` plus `repeat_rate=<float>`.
- Compare against the pre-change baseline from the read-only Discord audit; a
  `.feature` scenario is **not** claimed as passing from this.
- Rollback: none needed (read-only).

## Deferred handoff

Thread reuse, archival, and one-thread-per-key belong to
`homelab/docs/proposals/2026-09-15-cleytin-thread-lifecycle.md` (still Proposed).
Concrete insertion point for a future upstream change: the adapter's
auto-thread creation site guarded by `auto_threaded_channel is None`, described
in `hermes-agents.nix:234-237`. Do not duplicate that work here.

## Rollout

1. Slice 5 (gitops) lands first — Argus ignores the unknown token until Slice 2.
2. Slices 0-4 on `docs/argus-dedupe-plan-20261026` → PR → `just dry discovery` →
   `just switch-discovery` (recipe names per
   `cleytin-thread-lifecycle.md:162`) → `just hermes-argus-health` style check.
3. Watch one real repeat cycle and one resolved cycle in `#incidents`
   (read-only) before Slice 6.

## Verification summary

| Slice | Command | Marker |
|---|---|---|
| 0 | `python3 tests/argus-dedupe-probe.py` | `PASS argus-dedupe-probe` |
| 1, 3 | `python3 modules/hosts/discovery/hermes-plugins/alert-dedupe/selftest.py` | `PASS alert-dedupe-selftest` |
| 2, 4 | `python3 tests/argus-security/test_argus.py` | `PASS argus-security-contract` |
| 2 | `nix flake check --no-build` / `just dry discovery` | exit 0 |
| 5 | homelab-gitops template render | `PASS alert-template-key-token` |
| 6 | ledger stats one-liner | `PASS alert-dedupe-measure` |

No scenario in `argus-dedupe.feature` may be reported as passing until the
binding command prints its marker.

## Slice 5 outcome (2026-10-26)

Implemented as **instance counts on the omission line** only. The proposed
`key <family> @ <unix>` token was rejected: the parser already gets the stable
rule UID from the Rule URL Grafana appends, while a token built from
`alertname|host|unit` would create a second key namespace for the same alert
during rollout. The unit blind spot is covered by the plugin's
`systemd unit <name>` extraction, verified against real payloads.
