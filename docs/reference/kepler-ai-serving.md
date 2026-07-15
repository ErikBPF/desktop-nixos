# Kepler ai-serving — STT, TTS, and Embeddings

**Status:** Retired 2026-07-14. The topology below is historical. Kepler no
longer declares or starts this stack; its ports and model-cache tmpfiles were
removed. The seven runtime containers/images and `/fast/ai-models` were also
removed and verified absent after reboot. Reintroducing any model service
requires a new declarative Servarr stack and consumer-route review.

GPU-backed audio + embedding services running on Kepler's RTX 3070 (8 GB
VRAM), optimized for Brazilian Portuguese. All endpoints are reached through
LiteLLM on Discovery; nothing in this stack faces the public internet.

## Topology

```
                      ┌────────────────────────────────────────────────────────┐
                      │ Discovery (24/7 infra)                                 │
   external clients ──┤   SWAG (TLS, *.homelab.pastelariadev.com)              │
   hermes-agent ──────┤   LiteLLM gateway ──── whisper-pt-br ──────┼──► kepler:9000   (faster-whisper, pt-BR)
   HAOS VM ──────────-┤   model_list:          tts-pt-br ──────────┼──► kepler:8002   (edge-tts, Thalita)
   OpenWebUI / n8n ───┤                        tts-pt-br-piper ────┼──► kepler:8003   (piper-openai, faber)
│                        bge-m3 ─────────────┼──► kepler:8085   (TEI, BAAI/bge-m3, 1024-dim)
                       │                        bge-reranker-v2-m3 ─┼──► kepler:8087   (TEI, Cohere /v1/rerank)
                       │                        qwen-chat ──────────┼──► orion:8080    (Qwen3.6-35B-A3B)
                      │   piper-wyoming (legacy direct) ───────────┼──► kepler:10200  (Piper TTS, Wyoming TCP)
                      └────────────────────────────────────────────────────────┘
                                          ▲
                                          │ LAN / Tailscale
                      ┌───────────────────┴────────────────────────────────────┐
                      │ Kepler (NixOS, RTX 3070 8 GB)                          │
                      │   podman-compose ai-serving.yml                        │
                      │     • faster-whisper-openai    9000   STT (large-v3-turbo)
                      │     • edge-tts-openai          8002   TTS primary (Thalita +25%)
                      │     • piper-openai             8003   TTS offline fallback
                      │     • piper-wyoming           10200   TTS (Wyoming, legacy direct)
│     • tei-bge-m3              8085   embeddings (BAAI/bge-m3, 1024-dim)  ← sole GPU resident
│     • tei-reranker            8087   reranker (BAAI/bge-reranker-v2-m3, Cohere API)
│   models cached at /fast/ai-models                     │
                      └────────────────────────────────────────────────────────┘
```

**Invariant**: every consumer (hermes, HA, OpenWebUI, n8n, anything new) speaks
OpenAI to the LiteLLM gateway. There are no sanctioned direct-to-kepler paths
*except* the legacy Wyoming piper at `:10200`, which exists for HA announcement
use cases that predate the Phase 1 voice-assistant rollout and is being phased
out as Phase 1 lands. Adding a new route → edit `model_list` in
`servarr/machines/discovery/config/litellm/litellm_config.yaml`; never point a
new consumer at a Kepler port directly.

## History — services that came and went

- **`f5-tts-server`** (port 8001) — retired 2026-07-14. The experimental
  PT-BR voice-cloning service never became a LiteLLM route. Its Compose
  service, local build, model/reference artifacts, firewall exposure, and
  recovery provenance were removed together.
- **`faster-whisper-wyoming`** (port 10300) — removed 2026-05. `wyoming-faster-whisper 3.1.0` forces a stale `dropbox-dash/faster-whisper-large-v3-turbo` model that doesn't load on driver 595+. HA now reaches STT through the LiteLLM `whisper-pt-br` route (which lands at `:9000`, the OpenAI-shim variant), so no Wyoming STT is needed.
- **`infinity-embeddings`** (port 7997, `michaelf34/infinity:latest`, BAAI/bge-m3) — replaced 2026-05 by the llama.cpp `qwen3-embed` service on the same port. Same 1024-dim, same multilingual, higher MTEB, 32K context, Matryoshka. LiteLLM route name kept `embeddings-qwen3` either way; consumers don't move.
- **`qwen3-embed`** (port 7997, llama.cpp server-cuda, Qwen3-Embedding-0.6B) — **retired 2026-06**. A 38-query eval (exp001) showed R@1 0.55 vs 0.84 for BAAI/bge-m3. The permanent embedder is now `tei-bge-m3` (TEI, port 8085, LiteLLM model `bge-m3`, 1024-dim, MIT). A reranker was added in the same cycle: `tei-reranker` (TEI, port 8087, BAAI/bge-reranker-v2-m3, LiteLLM model `bge-reranker-v2-m3`, Apache-2.0, Cohere-style `/v1/rerank`, R@1 0.87).
- **Qwen2.5-VL-3B** (vision) — replaced 2026-05 by Qwen2.5-VL-7B-Instruct (Q4_K_M + f16 mmproj, mmproj kept on CPU via `--no-mmproj-offload`). Same `vision-qwen2vl` route; +5.5 MMMU, +75 OCRBench.
- **`gemma-vl`, `vision-qwen2vl`, and `gemma-chat`** — disabled 2026-06-29, then retired 2026-07-14. Gemma 4 E4B (~3.4 GB VRAM) co-resident with `qwen3-embed` (~3.1 GB) overcommitted the 8 GB GPU: embed `/health` stayed 200 but `/v1/embeddings` hung (llama.cpp `should_stop` task-cancel storm), silently breaking the LiteLLM `embeddings-qwen3` route (clients saw HTTP 000). The service, routes, Hermes auxiliary consumer, and port 8082 exposure were subsequently removed.

## Current container set

| Service | Image | Port | Health | LiteLLM route(s) |
|---------|-------|------|--------|------------------|
| `faster-whisper-openai` | `kepler/faster-whisper:cuda13` (locally built) | 9000 | `/health` | `whisper-pt-br` |
| `edge-tts-openai` | `kepler/edge-tts-openai:latest` (locally built) | 8002 | `/health` | `tts-pt-br` |
| `piper-openai` | `kepler/piper-openai:latest` (locally built) | 8003 | `/health` | `tts-pt-br-piper` |
| `tei-bge-m3` | `ghcr.io/huggingface/text-embeddings-inference:turing-1.7` | 8085 | `/health` | `bge-m3` (sole GPU resident) |
| `tei-reranker` | `ghcr.io/huggingface/text-embeddings-inference:turing-1.7` | 8087 | `/health` | `bge-reranker-v2-m3` (Cohere `/v1/rerank`) |
| `piper-wyoming` | `rhasspy/wyoming-piper:latest` | 10200 | `nc localhost 10200` | none (legacy direct, Wyoming protocol) |

## Components

| File | Purpose |
|------|---------|
| `modules/hosts/kepler/containers.nix` | Match fleet podman conventions, expose docker-compose |
| `modules/hosts/kepler/compose.nix` | Declares the `ai-serving` stack for `homelab.compose` |
| `modules/hosts/kepler/ai-serving.nix` | Firewall ports, `/fast/ai-models` tmpfiles |
| `servarr/machines/kepler/ai-serving.yml` | Compose definition for the 4 services |
| `servarr/machines/kepler/config/whisper/` | Dockerfile + FastAPI shim — required because upstream lscr.io/linuxserver/faster-whisper ships a CT2 runtime that rejects NVIDIA driver 595 |
| `servarr/machines/discovery/config/litellm/litellm_config.yaml` | Routes: `whisper-pt-br`, `tts-pt-br` (edge-tts), `tts-pt-br-piper`, `bge-m3`, `bge-reranker-v2-m3`, `qwen-chat` |
| `modules/hosts/discovery/hermes-agent.nix` | Wires the new routes into hermes auxiliary models |
| `machines/kepler/scripts/ai-smoke.sh` | End-to-end smoke test |

## Model selection (PT-BR)

| Service | Model | License | VRAM | Reasoning |
|---------|-------|---------|------|-----------|
| STT | `large-v3-turbo` via `faster-whisper` (CT2) | MIT | ~1.5 GB | 216× real-time at WER ~7.75% on PT-BR; LiteLLM route `whisper-pt-br`. Future swap → `freds0/distil-whisper-large-v3-ptbr` once CT2-converted (WER 8.22%, ~6× faster). |
| TTS — primary | Microsoft Edge TTS `pt-BR-ThalitaMultilingualNeural` at `+25%` rate | n/a (cloud, free tier) | CPU | Natural-sounding PT-BR neural voice; route `tts-pt-br`. Requires internet egress. |
| TTS — offline fallback | Piper `pt_BR-faber-medium` via OpenAI shim | MIT | CPU | Route `tts-pt-br-piper`. Local, no internet; lower quality. Wyoming variant at `:10200` exists for legacy HA direct hookups but is being phased out. |
| Embeddings | `BAAI/bge-m3` via TEI (`tei-bge-m3`) | MIT | ~1.0 GB | Route `bge-m3`. 1024-dim, multilingual, Matryoshka. Permanent choice per exp001 (38-query eval): R@1 0.84 vs 0.55 for qwen3-embed. |
| Reranker | `BAAI/bge-reranker-v2-m3` via TEI (`tei-reranker`) | Apache 2.0 | ~0.7 GB | Route `bge-reranker-v2-m3`, Cohere-style `/v1/rerank`. exp001 R@1 0.87. Port 8087 on Kepler. |

## Deploy

### 1. Build and switch the NixOS config

```sh
just switch-kepler        # nixos-rebuild switch on 192.168.10.230:2222
```

This:
- enables rootful Docker with the NVIDIA runtime,
- opens firewall ports 8002, 8003, 8085, 8087, 9000, 10200 (8001 retired
  with F5-TTS; 7997 retired with qwen3-embed; 8082 retired with Gemma;
  10300 retired with Wyoming whisper),
- pre-creates `/fast/ai-models/{whisper,embeddings,piper}`,
- enables the orchestration module so the compose stack is started on boot
  by the `podman-compose-ai-serving` user service (after `servarr-pull`
  refreshes the repo).

### 2. Sync the servarr repo + secrets

The `servarr-pull` user service fast-forwards `~/servarr` from GitHub and
decrypts `.env.sops` → `.env` via sops every boot. After the first deploy:

```sh
ssh -p 2222 erik@192.168.10.230 'systemctl --user status servarr-pull'
ssh -p 2222 erik@192.168.10.230 'cat ~/servarr/machines/kepler/.env | grep WHISPER'
```

If `.env.sops` is missing the AI-serving keys, encrypt the updated file
from your workstation:

```sh
cd ~/servarr
sops --input-type dotenv --output-type dotenv \
    -e machines/kepler/.env > machines/kepler/.env.sops
git commit -am "kepler: add AI-serving env" && git push
```

### 3. Start the stack

```sh
ssh -p 2222 erik@192.168.10.230 'cd ~/servarr/machines/kepler && just stack-up ai-serving'
```

First start downloads:
- `large-v3-turbo` whisper weights (~1.5 GB) → `/fast/ai-models/whisper`
- `BAAI/bge-m3` (~1.1 GB) → `/fast/ai-models/embeddings`
- `BAAI/bge-reranker-v2-m3` (~0.7 GB) → `/fast/ai-models/reranker`
- Piper PT-BR voice (~60 MB) → `/fast/ai-models/piper`

Allow 10–15 minutes for cold start. Watch progress:

```sh
ssh -p 2222 erik@192.168.10.230 'cd ~/servarr/machines/kepler && just ai-serving-logs'
```

### 4. Validate

```sh
just ai-kepler-health     # quick health probes for the serving stack
just ai-smoke             # full E2E (embedding + ASR + TTS + LiteLLM round-trip)
```

`ai-smoke` exits non-zero if any check fails.

## Home Assistant wiring

The current ("Phase 1") design routes HA's entire Assist pipeline through
LiteLLM — see the proposal at
`docs/implemented/2026-05-27-home-assistant-voice-assistant.md` and the
runbook at `<home-assistant-config>/docs/voice-assistant.md`.

**Earlier docs and earlier iterations of this file** suggested wiring HA's
Wyoming integration directly at `kepler:10300` (STT) and `kepler:10200`
(TTS), with the official **OpenAI Conversation** integration pointing at
the LiteLLM `base_url`. Both are now incorrect:

- The Wyoming faster-whisper service at `:10300` was retired (driver 595+ /
  CT2 incompatibility). HA reaches STT through LiteLLM's `whisper-pt-br`
  route (which lands at `:9000`).
- The official **OpenAI Conversation** integration hard-locks `base_url`
  to `api.openai.com` and can *not* talk to LiteLLM — never could. The
  Phase 1 design uses three vendored HACS components in
  `home-assistant-config/custom_components/`:
    - `openai_stt` (einToast, vendored with a one-line `vol.In` → `cv.string`
      patch so `whisper-pt-br` is an accepted model name) → STT.
    - `openai_tts` (sfortis) → TTS (model `tts-pt-br`, voice
      `pt-BR-ThalitaMultilingualNeural` sent explicitly, with the LiteLLM
      `sitecustomize.py` voice-default patch kept as belt-and-braces).
    - `custom_conversation` (michelle-avery, Phase 2) → conversation agent
      hitting LiteLLM `qwen-chat`, with HA Assist LLM API exposed for
      device control and "prefer handling commands locally" ON so device
      intents bypass the LLM when Orion is offline.

The Wyoming piper at `:10200` is still running as a legacy direct path for
HA *announcements* (broadcast TTS that pre-dates the LiteLLM-only design),
but is on track to retire as soon as the Phase 1 voice pipeline is stable.
No new HA integration should target it.

## Troubleshooting

### `ctranslate2.get_cuda_device_count() == 0` (GPU not visible to containers)

The compose file passes the GPU via CDI:

```yaml
devices:
  - nvidia.com/gpu=all
security_opt:
  - label=disable
```

`runtime: nvidia` in compose is silently ignored by Podman docker-compat —
containers come up under the `oci` runtime and `nvidia-smi` is absent
inside them. If a service logs `RuntimeError: CUDA failed with error CUDA
driver version is insufficient for CUDA runtime version`, the most common
cause is *no GPU at all* (not a driver mismatch). Verify:

```sh
docker inspect <container> --format '{{.HostConfig.Runtime}}'
docker exec <container> python -c "import ctranslate2; print(ctranslate2.get_cuda_device_count())"
```

If the runtime is `oci` and device count is `0`, the CDI device block was
dropped — re-sync `ai-serving.yml` and recreate the service.

### `wyoming-faster-whisper` cannot load `dropbox-dash/faster-whisper-large-v3-turbo`

Same error message as the CDI issue above, but caused by a stale CT2 model
spec. This Wyoming variant was removed from the stack — Home Assistant now
uses the OpenAI `/v1/audio/transcriptions` route via LiteLLM. If you bring
the Wyoming server back, supply `--model Systran/faster-whisper-large-v3-turbo`
or a pre-converted local path instead of the wyoming default.

### `faster-whisper-openai` returns 422 on `multipart/form-data`

The webservice expects the field name `audio_file`, not `file`. The smoke
script gets this right; clients calling directly should match.

### `infinity-embeddings` slow on first request

Infinity lazy-loads the model on first inference. Cold-start latency is
~10 s; subsequent requests are <100 ms. Pre-warm with the health probe.

### Whisper transcribes to English instead of Portuguese

Either `WHISPER_LANG=pt` is missing from `.env`, or the Wyoming client
overrode the language. Pin both in `.env` and in HA's STT integration.

## VRAM budget verification

Once everything is warm:

```sh
ssh -p 2222 erik@192.168.10.230 'nvtop -1'
```

Expect ~3–4 GB used across the active GPU containers (faster-whisper ~1.5 GB,
tei-bge-m3 ~1.0 GB, tei-reranker ~0.7 GB).

## License & data

- Whisper, Piper PT-BR voice, BAAI/bge-m3 (MIT), BAAI/bge-reranker-v2-m3 (Apache-2.0): permissive.
- All audio stays on Kepler; LiteLLM does not log payloads beyond Langfuse
  trace metadata (configurable in `litellm_config.yaml`).
