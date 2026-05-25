# Kepler ai-serving — STT, TTS, Embeddings, OCR-as-VLM

GPU-backed audio + embedding services running on Kepler's RTX 3070 (8 GB
VRAM), optimized for Brazilian Portuguese. All endpoints are reached through
LiteLLM on Discovery; nothing in this stack faces the public internet.

## Topology

```
                      ┌────────────────────────────────────────┐
                      │ Discovery (24/7 infra)                 │
   external clients ──┤   SWAG (TLS)                           │
   hermes-agent ──────┤   LiteLLM ─── auxiliary.transcription ─┼──► kepler:9000   (faster-whisper)
                      │            ─── auxiliary.tts ──────────┼──► kepler:8001   (F5-TTS)
                      │            ─── auxiliary.embeddings ───┼──► kepler:7997   (Infinity)
                      │   HAOS VM (Wyoming) ───────────────────┼──► kepler:10200  (Piper TTS)
                      │                       ─────────────────┼──► kepler:10300  (Whisper STT)
                      └────────────────────────────────────────┘
                                          ▲
                                          │ LAN / Tailscale
                      ┌───────────────────┴────────────────────┐
                      │ Kepler (NixOS, RTX 3070 8 GB)          │
                      │   docker compose ai-serving.yml        │
                      │     • faster-whisper-wyoming  10300    │
                      │     • faster-whisper-openai    9000    │
                      │     • piper-wyoming           10200    │
                      │     • f5-tts-server            8001    │
                      │     • infinity-embeddings      7997    │
                      │   models cached at /fast/ai-models     │
                      └────────────────────────────────────────┘
```

## Topology — actual deployed shape

The first iteration of this stack had five containers including a Wyoming
faster-whisper service for HA. After hitting an unfixable CT2 model
incompatibility in `wyoming-faster-whisper 3.1.0` (it forces a stale
`dropbox-dash/faster-whisper-large-v3-turbo` model that doesn't load on
driver 595), the Wyoming variant was dropped. HA reaches STT via the
OpenAI route at `kepler:9000` instead — `OpenAI Conversation` /
`OpenAI STT` integration in HAOS supports a custom base URL since 2025.7.

Final container set:

| Service | Image | Port | Health |
|---------|-------|------|--------|
| `faster-whisper-openai` | `kepler/faster-whisper:cuda13` (locally built) | 9000 | `/health` |
| `infinity-embeddings` | `michaelf34/infinity:latest` | 7997 | `/health` |
| `f5-tts-server` | `kepler/f5-tts-server:pt-br` (locally built) | 8001 | `/health` |
| `piper-wyoming` | `rhasspy/wyoming-piper:latest` | 10200 | `nc localhost 10200` |

## Components

| File | Purpose |
|------|---------|
| `modules/hosts/kepler/containers.nix` | Match fleet podman conventions, expose docker-compose |
| `modules/hosts/kepler/compose.nix` | Declares the `ai-serving` stack for `homelab.compose` |
| `modules/hosts/kepler/ai-serving.nix` | Firewall ports, `/fast/ai-models` tmpfiles |
| `servarr/machines/kepler/ai-serving.yml` | Compose definition for the 4 services |
| `servarr/machines/kepler/config/whisper/` | Dockerfile + FastAPI shim — required because upstream lscr.io/linuxserver/faster-whisper ships a CT2 runtime that rejects NVIDIA driver 595 |
| `servarr/machines/kepler/config/f5-tts/` | Dockerfile + FastAPI shim for F5-TTS PT-BR voice cloning |
| `servarr/machines/discovery/config/litellm/litellm_config.yaml` | Adds `whisper-pt-br`, `tts-pt-br-f5`, `embeddings-qwen3`, `vision-qwen2vl` routes |
| `modules/hosts/discovery/hermes-agent.nix` | Wires the new routes into hermes auxiliary models |
| `machines/kepler/scripts/ai-smoke.sh` | End-to-end smoke test |

## Model selection (PT-BR)

| Service | Model | License | VRAM | Reasoning |
|---------|-------|---------|------|-----------|
| STT (OpenAI) | `large-v3-turbo` via `faster-whisper` (CT2) | MIT | ~1.5 GB | 216× real-time at WER ~7.75% on PT-BR; future swap → `freds0/distil-whisper-large-v3-ptbr` once CT2-converted (WER 8.22%, ~6× faster) |
| TTS — voice cloning | `firstpixel/F5-TTS-pt-br` (DiT + flow matching) — model at `pt-br/model_last.pt`, vocab from `SWivid/F5-TTS` at `F5TTS_Base/vocab.txt` (firstpixel reuses the upstream char vocab) | CC BY-NC 4.0 | ~3.0 GB | ~10 s reference audio; non-autoregressive; switch `F5_MODEL_REPO=mrfakename/OpenF5-TTS-Base` for an Apache-2.0 base |
| TTS — HA fallback | Piper `pt_BR-faber-medium` | MIT | CPU | Low-latency announcements; no GPU |
| Embeddings | `BAAI/bge-m3` via Infinity (1024-dim, multilingual, 8k context) | MIT | ~1.3 GB | Replaces planned `Qwen/Qwen3-Embedding-0.6B` — current `michaelf34/infinity:latest` (9 months old) bundles transformers < 4.51 and cannot load qwen3 architecture. LiteLLM route name kept as `embeddings-qwen3` for downstream stability. |
| OCR / Vision | `Qwen2.5-VL` on Orion llama-server (no Kepler footprint) | Apache 2.0 | — | OCR-as-VLM: hermes-agent calls `vision-qwen2vl`; saves the 2 GB it would cost on Kepler |

## Deploy

### 1. Build and switch the NixOS config

```sh
just switch-kepler        # nixos-rebuild switch on 192.168.10.230:2222
```

This:
- enables rootful Docker with the NVIDIA runtime,
- opens firewall ports 7997, 8001, 9000, 10200, 10300,
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
- `Qwen3-Embedding-0.6B` (~1.3 GB) → `/fast/ai-models/embeddings`
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

After the stack is healthy, in the HAOS VM (192.168.10.115):

1. **Settings → Devices & services → Add Integration → Wyoming Protocol**
   - Host `kepler`, port `10300` → Faster-Whisper STT
   - Host `kepler`, port `10200` → Piper TTS
2. **Settings → Voice assistants → Add assistant**
   - STT: `Wyoming (faster-whisper)` (PT-BR auto-detected by `WHISPER_LANG=pt`)
   - TTS: `Wyoming (piper)` for short announcements, or call the F5-TTS API
     via a REST shell command for higher-quality responses.
   - Conversation agent: **OpenAI Conversation** pointing at
     `https://litellm.homelab.pastelariadev.com/v1` with model `qwen-chat`.

The custom F5-TTS endpoint is not Wyoming — HA can call it via a
`rest_command:` or by routing through LiteLLM's `/v1/audio/speech`.

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

Expect ~5.5–6.2 GB used across the three GPU containers. If usage drifts
above 7 GB, F5-TTS has likely cached intermediate tensors — restart it:

```sh
just ai-serving-restart f5-tts-server
```

## License & data

- Whisper, Piper PT-BR voice, Qwen3-Embedding, Qwen2.5-VL: permissive.
- F5-TTS PT-BR fine-tune: **non-commercial** (CC BY-NC 4.0). Either swap to
  an Apache-2.0 base or accept the constraint.
- All audio stays on Kepler; LiteLLM does not log payloads beyond Langfuse
  trace metadata (configurable in `litellm_config.yaml`).
