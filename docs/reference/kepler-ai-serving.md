# Kepler ai-serving — STT, TTS, Embeddings, OCR-as-VLM

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
                       │                        vision-qwen2vl ─────┼──► kepler:8082   (Gemma 4 E4B) **DISABLED 2026-06-29**
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
│     • f5-tts-server            8001   TTS voice cloning (not in LiteLLM yet)
│     • tei-bge-m3              8085   embeddings (BAAI/bge-m3, 1024-dim)  ← sole GPU resident
│     • tei-reranker            8087   reranker (BAAI/bge-reranker-v2-m3, Cohere API)
│     • gemma-vl                8082   vision/chat (Gemma 4 E4B)  **disabled — `vision` profile**
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

- **`faster-whisper-wyoming`** (port 10300) — removed 2026-05. `wyoming-faster-whisper 3.1.0` forces a stale `dropbox-dash/faster-whisper-large-v3-turbo` model that doesn't load on driver 595+. HA now reaches STT through the LiteLLM `whisper-pt-br` route (which lands at `:9000`, the OpenAI-shim variant), so no Wyoming STT is needed.
- **`infinity-embeddings`** (port 7997, `michaelf34/infinity:latest`, BAAI/bge-m3) — replaced 2026-05 by the llama.cpp `qwen3-embed` service on the same port. Same 1024-dim, same multilingual, higher MTEB, 32K context, Matryoshka. LiteLLM route name kept `embeddings-qwen3` either way; consumers don't move.
- **`qwen3-embed`** (port 7997, llama.cpp server-cuda, Qwen3-Embedding-0.6B) — **retired 2026-06**. A 38-query eval (exp001) showed R@1 0.55 vs 0.84 for BAAI/bge-m3. The permanent embedder is now `tei-bge-m3` (TEI, port 8085, LiteLLM model `bge-m3`, 1024-dim, MIT). A reranker was added in the same cycle: `tei-reranker` (TEI, port 8087, BAAI/bge-reranker-v2-m3, LiteLLM model `bge-reranker-v2-m3`, Apache-2.0, Cohere-style `/v1/rerank`, R@1 0.87).
- **Qwen2.5-VL-3B** (vision) — replaced 2026-05 by Qwen2.5-VL-7B-Instruct (Q4_K_M + f16 mmproj, mmproj kept on CPU via `--no-mmproj-offload`). Same `vision-qwen2vl` route; +5.5 MMMU, +75 OCRBench.
- **`gemma-vl` / `vision-qwen2vl` route** — **disabled 2026-06-29**. Gemma 4 E4B (~3.4 GB VRAM) co-resident with `qwen3-embed` (~3.1 GB) overcommits the 8 GB GPU: embed `/health` stays 200 but `/v1/embeddings` hangs (llama.cpp `should_stop` task-cancel storm), silently breaking the LiteLLM `embeddings-qwen3` route (clients saw HTTP 000). embed is 24/7 (hermes memory, HA RAG); vision is optional → `gemma-vl` moved behind the `vision` compose profile so `compose up -d` (boot, `kick-stack`) no longer starts it. `vision-qwen2vl` + `gemma-chat` LiteLLM routes are now **dead** until manual revive: `docker compose -p ai-serving --env-file .env -f ai-serving.yml --profile vision up -d gemma-vl` (stop embed first — two GPU llama-servers do not coexist). Reviving chat needs a dedicated GPU or smaller embed stack. See `references/repos/servarr/machines/kepler/ai-serving.yml` gemma-vl block.

## Current container set

| Service | Image | Port | Health | LiteLLM route(s) |
|---------|-------|------|--------|------------------|
| `faster-whisper-openai` | `kepler/faster-whisper:cuda13` (locally built) | 9000 | `/health` | `whisper-pt-br` |
| `edge-tts-openai` | `kepler/edge-tts-openai:latest` (locally built) | 8002 | `/health` | `tts-pt-br` |
| `piper-openai` | `kepler/piper-openai:latest` (locally built) | 8003 | `/health` | `tts-pt-br-piper` |
| `f5-tts-server` | `kepler/f5-tts-server:pt-br` (locally built) | 8001 | `/health` | none yet (Phase 4 voice-clone candidate) |
| `tei-bge-m3` | `ghcr.io/huggingface/text-embeddings-inference:turing-1.7` | 8085 | `/health` | `bge-m3` (sole GPU resident) |
| `tei-reranker` | `ghcr.io/huggingface/text-embeddings-inference:turing-1.7` | 8087 | `/health` | `bge-reranker-v2-m3` (Cohere `/v1/rerank`) |
| `gemma-vl` | `ghcr.io/ggml-org/llama.cpp:server-cuda` | 8082 | `/health` | `vision-qwen2vl`, `gemma-chat` — **DISABLED** (`vision` profile; see History) |
| `piper-wyoming` | `rhasspy/wyoming-piper:latest` | 10200 | `nc localhost 10200` | none (legacy direct, Wyoming protocol) |

## Components

| File | Purpose |
|------|---------|
| `modules/hosts/kepler/containers.nix` | Match fleet podman conventions, expose docker-compose |
| `modules/hosts/kepler/compose.nix` | Declares the `ai-serving` stack for `homelab.compose` |
| `modules/hosts/kepler/ai-serving.nix` | Firewall ports, `/fast/ai-models` tmpfiles |
| `servarr/machines/kepler/ai-serving.yml` | Compose definition for the 4 services |
| `servarr/machines/kepler/config/whisper/` | Dockerfile + FastAPI shim — required because upstream lscr.io/linuxserver/faster-whisper ships a CT2 runtime that rejects NVIDIA driver 595 |
| `servarr/machines/kepler/config/f5-tts/` | Dockerfile + FastAPI shim for F5-TTS PT-BR voice cloning |
| `servarr/machines/discovery/config/litellm/litellm_config.yaml` | Routes: `whisper-pt-br`, `tts-pt-br` (edge-tts), `tts-pt-br-piper`, `bge-m3`, `bge-reranker-v2-m3`, `vision-qwen2vl` (dead — backend disabled), `qwen-chat` |
| `modules/hosts/discovery/hermes-agent.nix` | Wires the new routes into hermes auxiliary models |
| `machines/kepler/scripts/ai-smoke.sh` | End-to-end smoke test |

## Model selection (PT-BR)

| Service | Model | License | VRAM | Reasoning |
|---------|-------|---------|------|-----------|
| STT | `large-v3-turbo` via `faster-whisper` (CT2) | MIT | ~1.5 GB | 216× real-time at WER ~7.75% on PT-BR; LiteLLM route `whisper-pt-br`. Future swap → `freds0/distil-whisper-large-v3-ptbr` once CT2-converted (WER 8.22%, ~6× faster). |
| TTS — primary | Microsoft Edge TTS `pt-BR-ThalitaMultilingualNeural` at `+25%` rate | n/a (cloud, free tier) | CPU | Natural-sounding PT-BR neural voice; route `tts-pt-br`. Requires internet egress. |
| TTS — offline fallback | Piper `pt_BR-faber-medium` via OpenAI shim | MIT | CPU | Route `tts-pt-br-piper`. Local, no internet; lower quality. Wyoming variant at `:10200` exists for legacy HA direct hookups but is being phased out. |
| TTS — voice cloning | `firstpixel/F5-TTS-pt-br` (DiT + flow matching) | CC BY-NC 4.0 | ~3.0 GB | Not yet routed through LiteLLM — Phase 4 voice-clone synergy. Switch `F5_MODEL_REPO=mrfakename/OpenF5-TTS-Base` for an Apache-2.0 base. |
| Embeddings | `BAAI/bge-m3` via TEI (`tei-bge-m3`) | MIT | ~1.0 GB | Route `bge-m3`. 1024-dim, multilingual, Matryoshka. Permanent choice per exp001 (38-query eval): R@1 0.84 vs 0.55 for qwen3-embed. |
| Reranker | `BAAI/bge-reranker-v2-m3` via TEI (`tei-reranker`) | Apache 2.0 | ~0.7 GB | Route `bge-reranker-v2-m3`, Cohere-style `/v1/rerank`. exp001 R@1 0.87. Port 8087 on Kepler. |
| OCR / Vision | `Gemma 4 E4B-it` via llama.cpp `server-cuda` | Apache 2.0 | ~3.4 GB | Route `vision-qwen2vl`. **DISABLED 2026-06-29** — backend behind `vision` profile, route dead. See History. Recap: Qwen2.5-VL-7B (2026-05) → Gemma 4 E4B (2026-06) → disabled (VRAM contention with the embed service wedged embeddings). Revive via `--profile vision` (stop embed first). |

## Deploy

### 1. Build and switch the NixOS config

```sh
just switch-kepler        # nixos-rebuild switch on 192.168.10.230:2222
```

This:
- enables rootful Docker with the NVIDIA runtime,
- opens firewall ports 8001, 8002, 8003, 8082, 8085, 8087, 9000, 10200 (7997 retired with qwen3-embed; 10300 retired with Wyoming whisper),
- pre-creates `/fast/ai-models/{whisper,f5-tts,embeddings,refs,piper}`,
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

### 3. Build the F5-TTS image

Custom image — not on a public registry. First boot the stack will fail
the `f5-tts-server` build pull because there is no `kepler/f5-tts-server`
remote tag. Build it once on Kepler:

```sh
ssh -p 2222 erik@192.168.10.230 'cd ~/servarr/machines/kepler && just ai-build'
```

This compiles a CUDA 12.1 PyTorch image with `f5-tts==1.0.7`, takes ~6 min
on the 3070, and is cached for subsequent rebuilds.

### 4. Drop in a PT-BR reference voice

F5-TTS needs ~10 s of clean PT-BR audio to clone. The container looks for
`/refs/default.wav` (override via `F5_DEFAULT_VOICE`):

```sh
scp -P 2222 my-voice.wav erik@192.168.10.230:/fast/ai-models/refs/default.wav
ssh -p 2222 erik@192.168.10.230 \
    'echo "transcrição exata do áudio de referência" > /fast/ai-models/refs/default.txt'
```

Without a reference, `/v1/audio/speech` returns HTTP 503.

### 5. Start the stack

```sh
ssh -p 2222 erik@192.168.10.230 'cd ~/servarr/machines/kepler && just stack-up ai-serving'
```

First start downloads:
- `large-v3-turbo` whisper weights (~1.5 GB) → `/fast/ai-models/whisper`
- `firstpixel/F5-TTS-pt-br` checkpoint + vocab (~3 GB) → `/fast/ai-models/f5-tts/hf`
- `BAAI/bge-m3` (~1.1 GB) → `/fast/ai-models/embeddings`
- `BAAI/bge-reranker-v2-m3` (~0.7 GB) → `/fast/ai-models/reranker`
- Piper PT-BR voice (~60 MB) → `/fast/ai-models/piper`

Allow 10–15 minutes for cold start. Watch progress:

```sh
ssh -p 2222 erik@192.168.10.230 'cd ~/servarr/machines/kepler && just ai-serving-logs'
```

### 6. Validate

```sh
just ai-kepler-health     # quick health probes for all 5 services
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

F5-TTS at `:8001` is intentionally **not** in `model_list` yet — it's the
Phase 4 voice-clone candidate. Adding it = one `model_name: tts-pt-br-f5`
entry in `litellm_config.yaml`; HA then picks it up via the same `openai_tts`
component by switching the configured model.

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

### F5-TTS build fails with `torchvision::nms does not exist`

`pip install f5-tts` will, if unconstrained, upgrade `torch` to 2.12 and
leave `torchaudio`/`torchvision` on 2.4 — at which point the C extensions
fail ABI checks. The Dockerfile uses a constraints file pinning the entire
torch trio to 2.4 and `transformers<4.50`. If you need newer transformers
in the future, upgrade torchvision in lockstep.

### F5-TTS exits with `Entry Not Found for url: .../vocab.txt`

`firstpixel/F5-TTS-pt-br` does not ship a vocab file — it reuses the upstream
char vocab. The server downloads vocab from `SWivid/F5-TTS` at
`F5TTS_Base/vocab.txt` (`F5_VOCAB_REPO` / `F5_VOCAB_FILE` env vars).
If you swap to a different fine-tune, point these at its vocab.

### `f5-tts-server` exits with `CUDA out of memory`

Two heavyweight models in VRAM at once (F5-TTS + Whisper turbo + Infinity)
leaves ~2 GB headroom. If a vision model is added on Kepler, F5-TTS will
OOM. Either:

- move the VLM to Orion (recommended — already configured in litellm),
- run F5-TTS at half precision: edit `config/f5-tts/server.py` to load the
  model with `torch.float16`, OR
- swap to `mrfakename/OpenF5-TTS-Base` which is lighter.

### `faster-whisper-openai` returns 422 on `multipart/form-data`

The webservice expects the field name `audio_file`, not `file`. The smoke
script gets this right; clients calling directly should match.

### `infinity-embeddings` slow on first request

Infinity lazy-loads the model on first inference. Cold-start latency is
~10 s; subsequent requests are <100 ms. Pre-warm with the health probe.

### Whisper transcribes to English instead of Portuguese

Either `WHISPER_LANG=pt` is missing from `.env`, or the Wyoming client
overrode the language. Pin both in `.env` and in HA's STT integration.

### `docker compose build` fails on the F5-TTS image

CUDA 12.1 base image requires the nvidia-container-toolkit to be installed
*and* the host's NVIDIA driver to be ≥ 535. Check:

```sh
nvidia-smi
docker info | grep -i runtime
```

## VRAM budget verification

Once everything is warm:

```sh
ssh -p 2222 erik@192.168.10.230 'nvtop -1'
```

Expect ~3–4 GB used across the active GPU containers (faster-whisper ~1.5 GB, tei-bge-m3 ~1.0 GB, tei-reranker ~0.7 GB). If usage drifts
above 7 GB, F5-TTS has likely cached intermediate tensors — restart it:

```sh
just ai-serving-restart f5-tts-server
```

## License & data

- Whisper, Piper PT-BR voice, BAAI/bge-m3 (MIT), BAAI/bge-reranker-v2-m3 (Apache-2.0): permissive.
- F5-TTS PT-BR fine-tune: **non-commercial** (CC BY-NC 4.0). Either swap to
  an Apache-2.0 base or accept the constraint.
- All audio stays on Kepler; LiteLLM does not log payloads beyond Langfuse
  trace metadata (configurable in `litellm_config.yaml`).
