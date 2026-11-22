# Voice inference through LiteLLM

**Stage / revision:** IP / 2
**Status:** Implementation underway; the deployed shortcuts still use local inference.
**Owner / date:** desktop-nixos, Servarr, homelab-iac / 2026-11-21

## Outcome and why

Human seed: “lets try to move voice stack to use our litellm instance and first path and local models as fallback. We can deploy models on orion and route them via litellm”. The migration covers transcription and contextual rewriting. Super+F8/F9/F10, clipboard-only output, capture-bound copied context, Portuguese/English, and cancellation remain the accepted behavior. Fetching copied URLs, app actions, transcript archives and meeting capture are outside this change.

Endeavour will send one closed audio recording to a dedicated LiteLLM transcription alias; contextual dictation additionally sends the transcript and the copied snapshot to a dedicated rewrite alias. Both aliases resolve only to Orion. Failure of an eligible primary call falls back once to Endeavour's existing Parakeet or Ollama model. No paid provider is allowed.

## Boundaries and delivery

Servarr owns an isolated CPU transcription workload on Orion. Its existing GPU chat endpoint serves rewriting; a second GPU model is unnecessary given approximately 13.35 GB of 17.10 GB VRAM already allocated. Desktop-nixos owns capture, shortcuts, fallback, host access and managed workload activation. Homelab-iac owns database-backed model aliases and a dedicated least-privilege key, mirrored into OpenBao. Secrets never enter Nix store or repository files.

Capture must retain the same WAV for both ASR attempts. The existing Voxtype daemon exposes only text, so PipeWire records a private 16 kHz mono PCM WAV. Recording stops and the process is reaped before network work starts. Local fallback uses pinned Voxtype 1.1.1's file transcription command with a strict parser. Audio is deleted on every terminal path. Successful empty transcription means no speech; it does not trigger fallback. Cancellation does not trigger fallback or clipboard writes. Authentication/configuration failures must be visible rather than silently hiding persistent degradation.

## Evidence and verification

Source and live read-only checks established a healthy LiteLLM readiness endpoint and Orion chat HTTP health. `/v1/models` identifies `qwen3.8-coder`. Its container still reports unhealthy, so inference quality and load remain unqualified. Orion has approximately 82 GiB available RAM and 257 GiB model-disk space.

The fresh independent plan review required explicit fallback classification, closed WAV validation, strict CLI parsing, local-only gateway routes and proof of privacy on success and failure. Current LiteLLM configuration stores prompts and sends Langfuse callbacks; real voice traffic remains disabled until a synthetic marker check qualifies the exclusion mechanism.

Tests will establish primary success bypassing local inference, one fallback with identical audio/context, silence preserving the clipboard, cancellation at every boundary, malformed/truncated responses, TLS verification, denied unrelated aliases and disconnected operation. Run `python3 -m unittest discover -s tests/voice-dictation`, existing rewrite fixtures, virtual-source E2E, Nix lint/format/docs checks and Endeavour/Orion dry builds for touched configurations. Unit checks cannot substitute for gateway privacy or deployed capture evidence.

## Continuing work and recovery

No new behavior decision is required. Orion is pinned to Servarr commit `2090849b39b1b1112c0d98580d202ebe6459a10a`, 43 commits behind current main. A broad pin update could replace its active chat experiment. Prepare the complete diff and owner rollout before changing it; do not bypass the pin. Gateway routes/key and client rollout follow backend qualification. Preserve current generated local-only units and bindings for scoped rollback. Do not activate unrelated Home Manager changes. Source is currently uncommitted; runtime success has not been claimed.
