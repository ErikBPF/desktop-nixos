# Home Assistant tool-caller shadow runtime

**Status:** Proposal — implementation-ready; no deployment approved
**Date:** 2026-07-16
**Owner:** erik
**Target host:** kepler
**Related:** [`2026-07-02-home-assistant-ai-consolidation.md`](2026-07-02-home-assistant-ai-consolidation.md), [`../reference/kepler-ai-serving.md`](../reference/kepler-ai-serving.md)

## Purpose

Define the smallest runtime needed to collect real Home Assistant transcripts,
evaluate the selected Qwen3-4B shadow candidate, and preserve the incumbent
voice path unchanged. A fresh engineer should be able to turn this design into
one cross-repository behavior contract without reviving the retired general
Kepler AI stack.

This phase is act-nothing. The candidate has no Home Assistant credential, no
dispatch interface, and no authority over the response returned to the user.

## Current boundary

The Kepler AI-serving stack was retired on 2026-07-14. Whisper, TTS,
embeddings, reranking, model caches, routes, ports, and lifecycle declarations
from that stack are not available building blocks. Their old capacity plan is
superseded.

Home Assistant already contains a disabled conversation proxy. It calls the
current conversation agent synchronously, returns that exact result, then
submits the transcript to a bounded asynchronous capture endpoint. Shadow
collection therefore consumes the incumbent transcript at the conversation
boundary. It does not restore or replace STT, TTS, wake-word handling,
satellites, entity exposure, or the incumbent conversation agent.

## Minimal topology

```text
Home Assistant
  incumbent conversation agent ──► authoritative response/action
              │
              └── bounded asynchronous transcript mirror
                         │ authenticated private request
                         ▼
Kepler: ha-shadow worker
  capture API ─► encrypted SQLite evidence ─► bounded replay queue
                                               │
                                               ▼
Discovery LiteLLM ─► Kepler: dedicated Qwen llama-server
                                               │
                                               ▼
                                  Rust harness, act-nothing replay
                                               │
                                               ▼
                                    trace in encrypted evidence
```

Three runtime processes are required on Kepler:

1. **`ha-shadow-worker`** — authenticated capture API, bounded queue, cohort
   metadata, circuit breakers, candidate client, and encrypted SQLite evidence.
2. **`ha-shadow-qwen`** — one dedicated llama-server for the selected
   Qwen3-4B v8 on-policy DPO Q5_K_M artifact, Q8 KV, pinned prompt, and
   entity-enumerating GBNF.
3. **`ha-shadow-harness`** — the Rust parser, context compiler, policy gate,
   and trace producer. It exposes replay/evaluation only; its build and runtime
   contain no Home Assistant token or dispatcher.

The worker calls the candidate through a dedicated LiteLLM alias. The
llama-server port is private to the service network or restricted to the
gateway. Home Assistant calls only the capture API; it never calls the
candidate route and never waits for candidate output.

The worker and harness may later share one container only if packaging proves
that this preserves separate failure reporting and the no-dispatch boundary.
They remain distinct responsibilities in the contract.

## Explicit exclusions

Do not restore the retired `ai-serving` stack. This slice excludes:

- Whisper, Edge TTS, Piper, F5-TTS, `bge-m3`, and the reranker;
- E2B audio-native serving;
- RAG or vector retrieval;
- replacement of the incumbent HA conversation agent;
- candidate dispatch, supervised canary, or autonomous action;
- an Orion production placement;
- reuse of old mutable model caches without hash verification.

If the incumbent voice path itself is unhealthy, repair it as a separate
incident. Do not broaden this shadow slice to replace it.

## Ownership and landing order

One owner remains authoritative for each concern:

| Concern | Owner |
|---|---|
| Model, grammar, worker, evidence schema, Rust harness | `ha-agent` |
| Kepler container definitions and lifecycle | `servarr` |
| Host storage, GPU/runtime support, firewall policy | `desktop-nixos` |
| LiteLLM alias, upstream registration, scoped key | `homelab-iac` |
| Disabled transcript mirror and later activation | `home-assistant-config` |

Land leaf changes in this order:

1. `ha-agent`: behavior contract, runnable entry points, images/artifact
   manifest, fake end-to-end test.
2. `servarr`: declarative shadow-only stack pinned to the published artifacts.
3. `desktop-nixos`: only host substrate proven necessary by the stack.
4. `homelab-iac`: candidate alias and capture/candidate credential scopes.
5. Capacity test on Kepler.
6. `home-assistant-config`: enable the existing mirror only after every prior
   gate passes.

No repository may read another working tree at build or deploy time. Publish
and pin artifacts between owners.

## Runtime and data contracts

- Capture requests use the versioned authenticated API already tested in
  `ha-agent`. Payload limits and path-traversal rejection remain mandatory.
- Queue saturation, candidate failure, gateway failure, and worker timeout
  drop only shadow work and record a reason. They never backpressure HA.
- Evidence storage must be an encrypted local mount. Startup fails when the
  deployment-provided encryption marker is absent.
- Raw transcripts and future audio references remain local. External telemetry
  receives only hashes, timings, counters, cohort identifiers, and redacted
  metadata.
- Every cohort pins model, grammar, entity snapshot, prompt, harness, driver,
  and serving configuration hashes. Behavior-changing updates start a new
  cohort.
- The worker uses a capture-only bearer token. Its LiteLLM key is restricted to
  the shadow candidate alias. Neither token grants Home Assistant API access.
- Health checks distinguish capture readiness, candidate readiness, harness
  readiness, queue saturation, and paused/breaker state.
- Stopping or removing all three shadow processes leaves the incumbent path
  healthy and requires no HA rollback while the proxy remains disabled.

## Gates before enabling the mirror

### Packaging and isolation

- Python and Rust suites pass from clean declared environments.
- Containerized fake candidate → harness → encrypted evidence test passes.
- Artifact, grammar, snapshot, prompt, and harness hashes match the cohort
  manifest.
- Network inspection proves no candidate or harness path can reach Home
  Assistant dispatch APIs.
- Restart and reboot preserve evidence and restore the paused/running state
  intentionally.

### Kepler capacity

Run the actual shadow-only stack, not historical estimates:

- warm the Qwen server and replay representative captures;
- run at least 20 incumbent voice requests during a ten-minute concurrent
  window;
- reject on GPU OOM, driver fault, thermal violation, or incumbent p95
  regression above 10%;
- require candidate availability of at least 99% within the three-second hard
  timeout;
- require successful candidate requests at p50 no more than one second and p95
  no more than two seconds;
- record VRAM, temperature, queue depth, drops, incumbent latency, and candidate
  latency in the cohort evidence.

The earlier 4,178 MiB-free Whisper measurement is historical evidence only. It
does not describe this post-retirement topology.

### Failure removal

Stop and remove the shadow stack, then prove the incumbent conversation path
still responds and acts normally. This test is required before the mirror is
selected in Home Assistant.

## Activation boundary

After all gates pass, enable the existing Home Assistant proxy and select it as
the conversation agent. Keep the incumbent agent configured inside the proxy.
The first production cohort is all-satellite, act-nothing capture under
`household_permissive_v1`.

Promotion beyond shadow remains governed by the consolidation plan: at least
200 fully reviewed real utterances, deterministic session-level 60/40
train/escrow assignment, zero incorrectly auto-executable unsafe proposals,
the paired non-inferiority confidence gate, and a separately approved live
canary. None of those authorize dispatch in this slice.

## Next artifact

Create the behavior seed in `ha-agent`, because it owns the first implementation
and publishable runtime artifacts. The seed should reference this design and
cover only packaging, authenticated capture, candidate replay through
LiteLLM, harness isolation, encrypted evidence, circuit breakers, fake
end-to-end behavior, and the Kepler capacity measurement interface.
