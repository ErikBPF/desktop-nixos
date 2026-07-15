# Home Assistant Intelligent Voice Assistant (LiteLLM-routed)

**Date:** 2026-05-27
**Status:** Implemented (audit 2026-07-02) — Phases 0–3 core shipped in
`home-assistant-config` (LiteLLM-routed whisper STT + openai_tts `83afe08`,
LLM brain via custom-conversation `3230105` then extended_openai_conversation
for web search `a53c175`, openWakeWord + Atom Echo live). §6 synergies
(camera vision, hermes MCP bridge, f5-tts clone, RAG memory, Alexa
announcements) are future enhancements — tracked as backlog decision A12 in
[`../proposals/2026-07-02-open-decisions-and-work.md`](../proposals/2026-07-02-open-decisions-and-work.md).
**Owner:** erik
**Target hosts:** `discovery` (HAOS + LiteLLM), `kepler` (STT/TTS/vision), `orion` (reasoning LLM)
**Related:** [`2026-05-23-home-assistant-declarative.md`](2026-05-23-home-assistant-declarative.md) — this proposal's config changes land in the `home-assistant-config` repo per that doc's implemented Phase 1 workflow.

---

## 1. Goal

Turn the existing Home Assistant instance into a fully local-first intelligent voice assistant in **PT-BR**, reusing the AI stack already deployed across the homelab. The assistant must:

- Listen (STT), reason (LLM), and respond (TTS) — all in Brazilian Portuguese.
- Control the house (Zigbee switches, IR-blaster AC/TV, scenes, WoL) by voice.
- Answer open-ended questions and hold conversation when the reasoning model is available.
- **Degrade gracefully** to deterministic device control when the reasoning model (`orion`) is offline.
- Route every model call through the **LiteLLM gateway** so each voice turn is traced/costed in Langfuse.

This is an *integration* proposal: ~80% of the required services already run. The work is wiring HA to them, not building them.

### Invariant — LiteLLM is the only egress

**Home Assistant never speaks directly to `kepler`, `orion`, or any other model host.** Every model call — STT, TTS, LLM, vision, embeddings, future agents — goes through the LiteLLM gateway at `https://litellm.homelab.pastelariadev.com/v1`. If a desired feature requires a backend that isn't reachable through a LiteLLM route, the fix is to **add the route to LiteLLM's `model_list`**, not to point HA at the upstream. This invariant is what makes Langfuse observability, key/budget scoping, fallback routing, and central rate-limiting work — bypassing it once breaks all of them silently.

---

## 2. Current State (baseline)

Everything below already exists and is reachable. STT/TTS/vision/embeddings live on `kepler`; reasoning on `orion`; the gateway + HAOS on `discovery`; all on a Tailscale mesh.

| Layer | Service | Host | Direct endpoint | LiteLLM model name |
|---|---|---|---|---|
| Reasoning LLM | Qwen3.6-35B-A3B MoE (llama.cpp) | orion:8080 | `http://orion:8080/v1` | `qwen-chat` |
| Vision | Qwen2.5-VL-3B (llama.cpp + mmproj) | kepler:8082 | `http://kepler:8082/v1` | `vision-qwen2vl` |
| STT | faster-whisper `large-v3-turbo`, lang=`pt` | kepler:9000 | `http://kepler:9000/v1` | `whisper-pt-br` |
| TTS (primary) | edge-tts `pt-BR-ThalitaMultilingualNeural` `+25%` | kepler:8002 | `http://kepler:8002/v1` | `tts-pt-br` |
| TTS (offline) | piper `pt_BR-faber-medium` | kepler:8003 | `http://kepler:8003/v1` | `tts-pt-br-piper` |
| TTS (Wyoming) | piper `pt_BR-faber-medium` | kepler:10200 | Wyoming TCP | — (not OpenAI) |
| TTS (clone) | F5-TTS PT-BR | kepler:8001 | `http://kepler:8001/v1` | — (not in model_list yet) |
| Embeddings | BAAI/bge-m3 (TEI) | kepler:8085 | `http://kepler:8085/v1` | `bge-m3` |
| Gateway | LiteLLM v1.86 + Langfuse traces | discovery (`:4000` docker-internal only) | `https://litellm.homelab.pastelariadev.com/v1` (SWAG vhost, LAN via split-DNS) | — |
| Agent | hermes-agent (Telegram + HTTP + tools) | discovery:8642/8644 | `https://hermes.homelab.pastelariadev.com/v1` | uses `qwen-chat` |
| HA | HAOS 17.3 / Core 2026.5.4 VM (bridge `br0`) | discovery → 192.168.10.115:8123 | — | — |

LiteLLM config (canonical): `servarr/machines/discovery/config/litellm/litellm_config.yaml`. A `sitecustomize.py` patch in the LiteLLM container defaults the missing `voice` parameter on `Router.aspeech()` to Thalita — TTS through the gateway depends on this patch staying in place (see Risks).

**HA side today:**

- `default_config` is on → `assist_pipeline`, built-in intent `conversation`, `media_source` all live.
- ~~"Only `tts: google_translate` is configured. No STT, no TTS-via-LiteLLM, no LLM agent bound to Assist."~~ **CORRECTED 2026-05-29 after live HAOS inspection:** the yaml only shows `tts: google_translate`, but UI-side (`.storage/`) a complete Wyoming-based Assist pipeline already exists — STT `Wyoming faster-whisper` at `192.168.10.112:10300` (now confirmed dead host, integration entry deleted), TTS `Wyoming Piper` via the local `core_piper` add-on at `core-piper:10200`, wake_word `Wyoming openWakeWord` via the local `core_openwakeword` add-on at `core-openwakeword:10400`, conversation `llama_conversation` (Ollama, points at `https://ollama.ai.pastelariadev.com:443`). The Atom Echo `m5stack-atom-echo-0a0284` at `192.168.10.109` is already bound. Phase 1 is therefore a **swap** of STT/TTS engines from local Wyoming add-ons to LiteLLM-routed components, not a fresh install. Phase 3 (wake word) is mostly already done — only need to rebind the Atom Echo's pipeline to the swapped one.
- `llama_conversation` (home-llm v0.4.6) is *vendored but unused as our brain* — it's built for tiny Home-3B models, weak tool-calling. Will be replaced.
- Whole-house Zigbee switches (Zemismart, via Z2M), IR-blaster AC/TV scripts, WoL switch, Alexa Echo `media_player.*`, Moonraker.
- One **M5Stack Atom Echo** voice satellite already in the house.

**Critical correction:** the official **OpenAI Conversation** integration hard-locks to `api.openai.com` (no `base_url`) — it *cannot* talk to LiteLLM. Any prior note suggesting "OpenAI Conversation → litellm" is wrong. A custom component is mandatory. ([HA OpenAI docs](https://www.home-assistant.io/integrations/openai_conversation/))

---

## 3. Locked Decisions

Confirmed with owner on 2026-05-27:

| # | Decision | Choice | Consequence |
|---|---|---|---|
| 1 | **Routing** | **All through LiteLLM** | STT, TTS, LLM, vision all go via the gateway. Every voice turn traced/costed in Langfuse. Cost: discovery is the voice-path SPOF; TTS can't use native Wyoming (it's not OpenAI protocol) → needs an OpenAI-TTS custom component. |
| 2 | **Brain** | **`custom-conversation`** (michelle-avery) | Native LiteLLM client + provider fallback + HA Assist LLM API. Replaces the vendored `home-llm`. |
| 3 | **Orion-offline fallback** | **Local intents only** | Pipeline prefers HA's built-in intent engine for recognized commands; only open-ended turns hit the LLM. When `orion` is down, device control still works; free-form Q&A returns a graceful "não consegui". Zero cost, fully local. |
| 4 | **Frontend (first cut)** | **Atom Echo + mobile** | Reuse the in-house Atom Echo + HA mobile-app Assist. Server-side `openWakeWord`. No new hardware. Voice PE satellites deferred. |

---

## 4. Target Architecture

```
                         ┌──────────────── discovery ────────────────┐
  Atom Echo (room)       │                                            │
  HA mobile app   ─────► │  HAOS 17.3 / Core 2026.5.4 (.115:8123)     │
       │                 │                                            │
   audio stream          │   Assist pipeline                          │
       │                 │   ├─ wake word: openWakeWord (add-on)      │
       ▼                 │   ├─ STT  ──► openai_whisper_cloud ──┐     │
   openWakeWord          │   ├─ agent: custom-conversation ──┐        │
                         │   │     (prefer local intents ON)  │        │
                         │   └─ TTS  ──► openai_tts ──────────┼──┐    │
                         │                                    │  │    │
                         │            LiteLLM :4000 (LAN) ◄───┴──┴────┤
                         └──────────────────│─────────────────────────┘
                                            │  (Langfuse traces every turn)
                  ┌─────────────────────────┼──────────────────────────┐
                  ▼                          ▼                          ▼
        kepler:9000 whisper-pt-br   kepler:8002 tts-pt-br        orion:8080 qwen-chat
        kepler:8082 vision-qwen2vl  (Thalita PT-BR)              (35B reasoning)
```

**Turn flow (orion up):**
1. Atom Echo streams audio → openWakeWord detects "Okay Nabu" → Assist starts.
2. STT: `openai_whisper_cloud` POSTs audio to LiteLLM `whisper-pt-br` → kepler:9000 → text.
3. Agent: text → `custom-conversation`. *Prefer-local-intents*: if it matches an HA intent ("acende a luz da sala") → handled by HA's built-in intent engine, deterministic, no LLM. Otherwise → LiteLLM `qwen-chat` (orion), with HA's Assist LLM API exposed as tools so the model can also call services.
4. TTS: response text → `openai_tts` → LiteLLM `tts-pt-br` → kepler:8002 (Thalita) → audio back to Echo.
5. Langfuse records STT + LLM + TTS spans with latency + cost.

**Turn flow (orion down):**
- Steps 1–2 unchanged (STT is on kepler, independent of orion).
- Step 3: device commands still resolve via local intents. Open-ended turns → LLM call errors → graceful PT-BR failure message.
- Step 4 unchanged (TTS on kepler).

**Endpoint choice (verified 2026-05-27):** use `https://litellm.homelab.pastelariadev.com/v1`. Preflight found LiteLLM's `:4000` is **docker-internal only** (no host port mapping) — *not* reachable on the LAN, so the obvious `http://192.168.10.210:4000` does **not** work. But AdGuard (on discovery, `192.168.10.210:53`) split-DNS-rewrites `*.homelab.pastelariadev.com` → `192.168.10.210`, and SWAG nginx listens on `0.0.0.0:443` on the discovery host. So the vhost resolves to the LAN IP and terminates locally at SWAG → litellm:4000 — **no cloudflared round-trip**. Confirmed: `curl https://litellm.homelab.pastelariadev.com/v1/models` → `HTTP 401 via 192.168.10.210` (reached LiteLLM, on LAN), `/health/liveliness` → `200`. This is the same path hermes-agent already uses. Phase 0 check is therefore **DNS** (HAOS VM must use AdGuard `192.168.10.210` as resolver), not firewall.

---

## 5. Component Selection

### 5.1 STT — `openai_whisper_cloud` (fabio-garavini)

OpenAI-compatible STT for the Assist pipeline with **config_flow** + a "Custom" provider option that accepts arbitrary base URL and free-text model name. ([repo](https://github.com/fabio-garavini/ha-openai-whisper-stt-api))

**Earlier-iteration note:** this proposal initially picked `einToast/openai_stt_ha`. We vendored, patched its `vol.In(SUPPORTED_MODELS)` enum guard to `cv.string` to accept `whisper-pt-br`, deployed to live HAOS — and HA Core 2026.5.4 then rejected the integration entirely with *"The stt integration does not support any configuration parameters, got [...]. Please remove the configuration parameters from your configuration."* The yaml `stt:` list-platform mechanism was removed in HA `>=2023.7`; STT integrations now have to be `config_flow`-only. einToast's component is yaml-config and has no config_flow file. Swapped to fabio-garavini on 2026-05-29. The new component covers both gaps: config_flow (required by current HA) and arbitrary model strings (required by `whisper-pt-br`).

- **Provider**: `Custom` (index `3` in the dropdown; the OpenAI/GroqCloud/Mistral built-in providers all hit their respective `/v1/models/<id>` endpoint to validate, which LiteLLM doesn't honor the same way).
- **Name**: `LiteLLM Whisper PT-BR`
- **URL**: `https://litellm.homelab.pastelariadev.com` (base URL — the component appends `/v1/audio/transcriptions` itself)
- **API key**: ha-voice virtual key (see Phase 0 / §3 of the proposal)
- **Model**: `whisper-pt-br`
- Pipeline `stt_language`: `pt` (the component passes this through to LiteLLM's `language` form field; kepler's faster-whisper container also forces `WHISPER_LANG=pt` upstream, so this is belt-and-braces)

Alternative considered & rejected: re-adding Wyoming faster-whisper — blocked by the CUDA 595+ / CT2 mismatch that got it removed. The OpenAI shim on kepler:9000 already works and satisfies "all through LiteLLM".

### 5.2 Conversation agent — `custom-conversation` (michelle-avery)

Native LiteLLM support, multi-provider fallback, and a choice of exposed LLM API (None / Assist / its own). Purpose-built for this exact setup. ([repo](https://github.com/michelle-avery/custom-conversation))

- Provider: OpenAI-compatible via LiteLLM, `base_url` = `https://litellm.homelab.pastelariadev.com/v1`, key = master key.
- Model: `qwen-chat`.
- LLM API exposed: **Assist** (lets the model read/control exposed entities through HA intents/tools).
- **Prefer handling commands locally: ON** — recognized device intents bypass the LLM (fast, deterministic, orion-independent). This *is* the Decision #3 fallback mechanism.
- System prompt: PT-BR persona, concise spoken-style answers, house context.

Replaces vendored `home-llm`. `extended_openai_conversation` was the runner-up (mature function-calling, custom base_url) but lacks built-in provider fallback and needs hand-written function specs.

### 5.3 TTS — OpenAI-TTS custom component

"All through LiteLLM" rules out the native Wyoming piper (kepler:10200) because Wyoming isn't the OpenAI protocol LiteLLM speaks. Use an OpenAI-compatible TTS component (e.g. `sfortis/openai_tts`, supports custom base URL) pointed at the gateway.

- `url`/`base_url`: `https://litellm.homelab.pastelariadev.com/v1`
- `api_key`: master key
- `model`: `tts-pt-br` (edge-tts Thalita)
- voice: omit → LiteLLM `sitecustomize.py` patch defaults it to Thalita. (Or pass explicitly to avoid depending on the patch — see Risks.)

`tts-pt-br-piper` (kepler:8003) is the offline fallback voice; `f5-tts` (kepler:8001) is a later "voice clone" upgrade once added to the LiteLLM `model_list`.

### 5.4 Vision — `vision-qwen2vl` via LLM tool / AI Task (synergy, Phase 4)

Not part of the core voice loop. Wired as an AI Task / script so the assistant can describe a camera snapshot ("quem está na varanda?") by POSTing the image to the LiteLLM gateway with `model: vision-qwen2vl` — LiteLLM forwards to kepler:8082. HA never opens a connection to kepler directly (Invariant, §1).

### 5.5 Wake word + satellites

- **openWakeWord** add-on on HAOS (server-side) — the Atom Echo just streams audio; all detection happens on HA. Default "Okay Nabu"; custom wake word trainable later. ([HA wake word docs](https://www.home-assistant.io/voice_control/about_wake_word/))
  *Live state (2026-05-29):* `core_openwakeword` v2.1.0 add-on is already installed, started, and wired into the active pipeline via the Wyoming integration at `core-openwakeword:10400`. Phase 3 = rebind the Atom Echo's pipeline to whichever Assist pipeline Phase 1's swap produced; the add-on itself needs no install.
- Bind the Atom Echo (ESPHome integration → "Use wake word" → select this assistant's pipeline). *Live state:* `m5stack-atom-echo-0a0284` at `192.168.10.109` is already bound to the current pipeline.
- HA mobile app Assist uses the same pipeline (no wake word; press-to-talk).

---

## 6. Synergies (beyond the core loop)

Ranked by value/effort. Core loop is §4–5; these are follow-ups.

| Synergy | What | Effort |
|---|---|---|
| **Camera + vision** | Camera snapshot → LiteLLM `vision-qwen2vl` (upstream: kepler) → spoken description ("uma pessoa de jaqueta azul na porta"). Doorbell automation or voice-triggered. | Low |
| **Langfuse observability** | Every voice turn already traced once routed through LiteLLM — build a dashboard for STT/LLM/TTS latency + cost per turn. Free. | Low |
| **hermes-agent as super-brain** | HA's built-in **MCP Server** exposes entities as tools; `hermes-agent` (already on LiteLLM, Telegram, tool-calling) becomes one agent for house + homelab. Or hermes drives HA via its webhook (8644). Powerful but needs a bridge (hermes isn't a streaming Assist conversation entity). | High |
| **f5-tts voice clone** | Add `tts-pt-br-f5` to the LiteLLM `model_list`, clone a custom assistant voice. | Medium |
| **Embeddings memory/RAG** | `bge-m3` for semantic memory or RAG over house docs/notes the assistant can cite. | Medium |
| **Alexa Echo announcements** | Existing `media_player.*` Echos as TTS announcement targets ("avisa na cozinha que o jantar está pronto"). | Low |

---

## 7. Phased Implementation

All HA-config changes follow the declarative repo workflow (`home-assistant-config`, vendor custom_components into git, PR-driven). Nix-side changes are minimal — the AI services already run.

### Phase 0 — Connectivity preflight

**Partial results (run 2026-05-27 from laptop / discovery):**
- ✅ kepler routes reachable: `:9000` STT, `:8002` TTS, `:8082` vision, `:7997` embed — all OPEN.
- ✅ orion `:8080` (qwen-chat) OPEN.
- ❌ discovery `:4000` LiteLLM **not** on LAN (docker-internal only) — do not target it directly.
- ✅ `https://litellm.homelab.pastelariadev.com/v1` reachable **on LAN** via AdGuard split-DNS → SWAG: `/v1/models` → `401 via 192.168.10.210`, `/health/liveliness` → `200`. **This is the endpoint.**

**Remaining preflight steps:**
1. Confirm the **HAOS VM** uses AdGuard (`192.168.10.210`) as its DNS resolver so the vhost resolves to the LAN IP (not the public Cloudflare path). Test from inside HAOS: `nslookup litellm.homelab.pastelariadev.com` should return `192.168.10.210`.
2. Smoke-test each route with `curl` from the HAOS VM using a real key: `whisper-pt-br` (transcription), `tts-pt-br` (speech), `qwen-chat` (chat) — confirm 200s.
3. Mint a **scoped LiteLLM virtual key** for HA (model allowlist + budget) and store it as `litellm_master_key` in HA `secrets.yaml` (gitignored).

### Phase 1 — STT + TTS (voice I/O, no brain yet)
1. Vendor `custom_components/openai_whisper_cloud/` (fabio-garavini) and `custom_components/openai_tts/` (sfortis) into the repo; PR. *(Earlier iteration vendored einToast `openai_stt`; it's incompatible with HA Core 2026.5.4 and was removed before the PR landed — see §5.1.)*
2. Configure both pointing at LiteLLM (§5.1, §5.3). Both are UI-only (config_flow); walk via supervisor proxy API or click through the UI. Runbook in `home-assistant-config/docs/voice-assistant.md`.
3. **Swap, not add:** the live HAOS already has a Wyoming-based Assist pipeline (STT `stt.faster_whisper`, TTS `tts.piper`, conv `llama_conversation`, wake `wake_word.openwakeword`). Phase 1 edits `.storage/assist_pipeline.pipelines` to repoint `stt_engine` → `stt.litellm_whisper_pt_br` and (later) `tts_engine` → new openai_tts profile entity, while keeping `wake_word.openwakeword` (Phase 3 already done) and `tts.piper` (until openai_tts profile subentry is configured).
4. Validate end-to-end voice control of one light via the Atom Echo, fully through LiteLLM. Confirm Langfuse shows STT + TTS spans.

### Phase 2 — LLM brain
1. Vendor `custom_components/custom_conversation/`; PR. Remove `llama_conversation`.
2. Configure provider = LiteLLM, model = `qwen-chat`, LLM API = Assist, **prefer-local-intents ON**, PT-BR system prompt (§5.2).
3. Swap the pipeline's agent to `custom-conversation`.
4. Test: device command (local intent path) + open-ended question (LLM path) + orion-offline behavior (device control survives, Q&A fails gracefully).

### Phase 3 — Wake word + satellites
1. Install `openWakeWord` add-on; configure via Wyoming integration.
2. Bind Atom Echo + mobile app to the pipeline; enable wake word.
3. Tune "finished speaking" silence detection for the Atom Echo.

### Phase 4 — Synergies
- Camera-describe AI Task (`vision-qwen2vl`).
- Langfuse voice dashboard.
- Optional: f5-tts voice clone, hermes MCP bridge, embeddings memory.

---

## 8. Open Questions

- ~~**LiteLLM LAN exposure**~~ — **RESOLVED (2026-05-27 preflight):** `:4000` is docker-internal only, but the SWAG vhost `https://litellm.homelab.pastelariadev.com/v1` resolves to the LAN IP via AdGuard split-DNS and terminates locally (no cloudflared hop). Verified `401 via 192.168.10.210` + health `200`. Use the vhost.
- **HAOS VM DNS:** confirm the HAOS VM uses AdGuard (`192.168.10.210`) as its resolver, so the vhost resolves to the LAN IP rather than the public Cloudflare path. (DHCP on `br0` should hand this out; verify.)
- **Master key in HA:** acceptable to keep `litellm_master_key` in HA's `secrets.yaml`, or mint a scoped LiteLLM virtual key for HA with per-key budget/limits (cleaner, recommended)?
- **Latency budget:** measure STT→first-token→TTS end-to-end through the gateway on the Atom Echo. If LLM time-to-first-token is the bottleneck, consider streaming TTS.
- **TTS voice param:** rely on the `sitecustomize.py` default, or pass `voice` explicitly from the component to decouple from that patch?
- **Local-intent coverage:** is the built-in intent set + custom sentences enough for the common commands, so the orion-down experience is genuinely useful?

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| **discovery is the voice-path SPOF** (consequence of all-through-LiteLLM) | Accepted per Decision #1. discovery is the 24/7 host anyway; HA itself runs on it. |
| **LiteLLM `sitecustomize.py` voice patch lost** → TTS 500s | Pass `voice` explicitly from the TTS component, or pin/test the patch in CI for the LiteLLM image. |
| **cloudflared round-trip latency** if the vhost resolved via Cloudflare instead of LAN | Mitigated by AdGuard split-DNS (vhost → `192.168.10.210` → local SWAG). Verified LAN-local in preflight. Depends on HAOS VM using AdGuard as resolver (Phase 0 check). |
| **orion offline** → no free-form Q&A | By design (Decision #3): local intents keep device control working; Q&A fails gracefully. Revisit "always-on small local model" if the gap annoys. |
| **custom-conversation maturity** / OpenAI Responses-API drift | It uses the `litellm` library against chat-completions (LiteLLM supports it), not the Responses API that broke the older `openai-compatible-conversation`. Pin the component commit when vendoring. |
| **Master key blast radius** in HA secrets | Mint a scoped LiteLLM virtual key for HA (budget + model allowlist). |
| **Atom Echo is a single low-end satellite** | Acceptable for first cut; Voice PE units are the planned upgrade (deferred frontend scope). |

---

## 10. References

**Conversation agents (LiteLLM-capable):**
- [`custom-conversation` (michelle-avery)](https://github.com/michelle-avery/custom-conversation) — native LiteLLM + fallback + Assist API (chosen brain)
- [`extended_openai_conversation` (jekalmin)](https://github.com/jekalmin/extended_openai_conversation) — function-calling, custom base_url (runner-up)
- [`openai-compatible-conversation` (michelle-avery)](https://github.com/michelle-avery/openai-compatible-conversation) — base-url fork, superseded by custom-conversation
- [`hass_local_openai_llm` (skye-harris)](https://github.com/skye-harris/hass_local_openai_llm) — local OpenAI-compatible agent
- [Generic OpenAI-compatible component discussion #1681](https://github.com/orgs/home-assistant/discussions/1681) — why the official integration can't reach LiteLLM
- [Official OpenAI Conversation docs](https://www.home-assistant.io/integrations/openai_conversation/) — confirms hard-lock to api.openai.com

**STT:**
- [`openai_whisper_cloud` (fabio-garavini)](https://github.com/fabio-garavini/ha-openai-whisper-stt-api) — config_flow STT, multi-provider + Custom endpoint, free-text model. **Chosen 2026-05-29.**
- [`openai_stt_ha` (einToast)](https://github.com/einToast/openai_stt_ha) — OpenAI-API STT with custom `api_url`. **Was chosen, then rejected**: yaml-config only, HA `>=2023.7` no longer accepts list-platform `stt:` block.
- [`AlexxIT/FasterWhisper`](https://github.com/AlexxIT/FasterWhisper) — Wyoming/whisper custom integration (rejected: CUDA mismatch)
- [Set up a fully local voice assistant (HA)](https://www.home-assistant.io/voice_control/voice_remote_local_assistant/)
- [Speech-to-Phrase — Voice chapter 9](https://www.home-assistant.io/blog/2025/02/13/voice-chapter-9-speech-to-phrase/) — ultra-light local STT alternative

**TTS:** OpenAI-TTS custom component (`sfortis/openai_tts`-style) pointed at LiteLLM `tts-pt-br`.

**Wake word + satellites:**
- [The HA approach to wake words](https://www.home-assistant.io/voice_control/about_wake_word/)
- [Wake words for Assist](https://www.home-assistant.io/voice_control/create_wake_word/)
- [Voice chapter 10 — next iteration](https://www.home-assistant.io/blog/2025/06/25/voice-chapter-10/)
- [$13 voice assistant (Atom Echo)](https://www.home-assistant.io/voice_control/thirteen-usd-voice-remote/)
- [ESPHome Voice Assistant component](https://esphome.io/components/voice_assistant/)

**Architecture / background:**
- [Building the AI-powered local smart home (HA blog, 2025-09)](https://www.home-assistant.io/blog/2025/09/11/ai-in-home-assistant/) — MCP + AI Tasks
- [Create a personality with AI (HA)](https://www.home-assistant.io/voice_control/assist_create_open_ai_personality/)
