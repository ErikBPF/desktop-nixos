# Voice routing through LiteLLM — deployed with rewrite fallback

**Stage / revision:** RV / 4
**Status:** Orion ASR and Endeavour gateway-first capture deployed; remote rewrite degraded.
**Owner / date:** desktop-nixos, Servarr, homelab-iac / 2026-11-21

Current source review and merge gates: [PR #517 merge readiness](merge-readiness.md). The runtime evidence below remains historical.

## Outcome and why

Human seed: “lets try to move voice stack to use our litellm instance and first path and local models as fallback. We can deploy models on orion and route them via litellm”. Endeavour now tries the homelab gateway for transcription and contextual rewriting, with local Parakeet and Ollama fallback. Super+U dictates; Super+I snapshots copied context and rewrites the spoken instruction; Super+Ctrl+I cancels. Output is copied, never automatically pasted. URLs are not fetched.

## Changes and boundaries

IaC declares `voice-transcribe` and `qwen3.8-flash-next`, plus the key `svc-homelab-iac-voice-dictation-model-inference` scoped to exactly those two models (25 USD / 30 d, 2 parallel, 20 rpm, 1M tpm, `store_prompts_in_spend_logs=false`). The client reads `VOICE_LITELLM_API_KEY` from OpenBao `secret/home/voice-litellm`; Endeavour caches it in a mode-0600 file outside the Nix store. The sanctioned Sops bootstrap credential applied only the two voice policy paths, preserving the existing Cloudflare read permission. The normal AppRole then wrote the KV value; it still cannot edit its own policy. No paid-cloud route was added.

Servarr PR363 merged with the explicitly approved merge-commit exception. Its temporary repository merge setting was restored to squash-only. Orion pins the isolated artifact `f991f2cfe84bfd43f14aa47c147439704ebcfa79`, excluding the unrelated backlog. CPU Whisper large-v3-turbo runs in the independent voice stack. Discovery reaches its health endpoint; direct Endeavour access is denied. Isolation depends on both host firewall and Tailscale policy.

The client sends a closed private WAV and reuses it on eligible fallback. Silence and cancellation do not trigger fallback. Invalid results preserve the clipboard; audio is removed on every terminal path. Gateway retries and fallback are disabled, TLS verified, redirects rejected. Endeavour received only the tested voice units and three bindings; unrelated live Hyprland settings were preserved. The prior local generation remains rooted for recovery.

## Evidence and limits

27 unit tests, six existing IaC key contracts, Compose checks, Nix lint/format, Home Manager build and host dry-builds passed. Installed E2E passed synthetic capture through the real controller and services: primary ASR, contextual rewrite fallback, forced local ASR/rewrite, clipboard persistence, cancellation and temporary-audio cleanup. An isolated headless Wayland clipboard protected the user's selection. Plain mode took 10.39 seconds; contextual mode 16.91 seconds; forced local mode 5.99 seconds. Physical microphone and hardware keypress behavior remain untested.

Direct gateway English and Portuguese ASR passed in 14.4 and 12.43 seconds. Orion's existing GPU rewrite remained stuck loading after one owner-managed restart; no GPU reset or reboot was attempted. Scheduled Podman healthchecks report a conmon exec-pidfile failure affecting multiple existing containers; actual ASR health and inference pass. Container health metadata is therefore not green.

Only `voice-transcribe` carries `no-log=true`; `qwen3.8-flash-next` does not, so rewrite prompts rest on the key's `store_prompts_in_spend_logs=false` metadata alone. A synthetic failed rewrite had one identifiable accounting row and no content marker in recent rows. Successful ASR had no identifiable accounting row, and Langfuse queries timed out. These observations do not prove universal content exclusion, especially diagnostic errors. Only synthetic speech/context was used for qualification.

## Continuing work and recovery

Resolve Orion GPU availability and host scheduled-exec health separately; complete privacy observation before claiming zero-content logging. Client/IaC source is prepared for PR review; merge integration remains pending, and a later unrelated Home Manager activation can remove the scoped deployment. Migration paths and prior unit/config targets are recorded privately at `~/.local/state/voice-dictation/litellm-migration-paths.json`; restore those targets and reload services/Hyprland to recover the previous local flow. No archive, meeting capture or graph ingestion was added.

## Shortcut revision — 2026-11-23

User requested the two voice shortcuts on Super+U and Super+I. Plain dictation moved to Super+U and copied-context dictation to Super+I; Super+Ctrl+I still cancels. Removed the conflicting Super+U monitors-panel binding (the Super+I network-panel binding was already removed by the 2026-11-22 revision). Only declarative source changed; no activation or live keypress check was performed.

## Shortcut revision — 2026-11-22

User requested Super+I for plain dictation, Super+Shift+I for copied-context dictation, and Super+Ctrl+I for cancellation. Removed the conflicting Super+I network-panel binding. Updated declarative bindings and the recording notification. Scoped activation preserves other live desktop settings. This key remapping does not establish a fix for the previously reported capture symptom; microphone selection remains unconfirmed.

Validation: 27 controller tests and source binding assertions passed; live Hyprland reports exactly the three I-key bindings and no former Super+F8/F9/F10 bindings, with no configuration errors. Full Home Manager build was interrupted while waiting on the remote builder; scoped immutable config/unit/source activation changed only bindings and notification text. Prior targets are recorded in `~/.local/state/voice-dictation/shortcuts-2026-11-22.json`. No microphone capture or clipboard access was used for this remapping check.

## Fresh-install prerequisites

Activation provides the clients and services, but does not fetch the private gateway key or seed Ollama. Use the authorized OpenBao reader to retrieve only `VOICE_LITELLM_API_KEY` from `secret/home/voice-litellm` into `~/.config/voice-dictation/litellm-api-key` (parent directory mode0700, file mode0600). Never paste the value into a shell argument, journal, Nix expression or review artifact. Missing credentials select local fallback.

Start `voice-rewrite.service`, then seed its dedicated storage with `OLLAMA_HOST=127.0.0.1:11435 ollama pull qwen3.5:4b`. Verify `http://127.0.0.1:11435/api/tags` reports model `qwen3.5:4b` and digest `d8b0f5e9760cd1682034f292d7ef72ec46f432149be0df7574bf2d6e92e38c04` before claiming the observed local qualification applies. A mutable tag resolving differently requires new qualification. Parakeet files are checksum-pinned by Nix. The live local rewrite evaluator now explicitly disables gateway access.

Publication review (2026-11-22): rebased onto Orion wiring and current main. Added fresh-install model/key prerequisites and forced the local rewrite evaluator to bypass gateway access. All four local synthetic rewrite cases passed again; 27 controller tests, Nix lint/format and documentation checks passed. Physical-microphone behavior remains unresolved.

## PR517 CI reconciliation — 2026-11-22

The repository hygiene check rejected an unregistered `tests/voice-dictation` directory. Added its automated unit tests to the actual CI pytest invocation, rather than marking the suite manual. The synthetic live evaluators retain their explicit manual entry points and are not pytest-collected. The failing assertion and the passing hygiene plus voice suite record RED/GREEN. No runtime capture or deployment changed; personal microphone qualification remains open.

## Recorder reliability review correction — 2026-11-22

`wait_for_stop(process)` now checks for recorder death every 200 ms while retaining the 115-second monotonic deadline. The existing finally block still reaps the child; `dictate` still deletes partial audio and never transcribes or writes the clipboard after this failure. The RED run reproduced the previous 115-second blind wait; the green run passed 34 hygiene/voice tests, including prompt failure, cleanup and the duration limit. Independent reviewer `voice_research_review` inspected this diff and reported: “Recorder polling preserves the deadline and fails promptly on process death; 29 unit tests passed.” No live microphone was accessed by that review.

A later read-only desktop check found the default NoiseTorch source muted. The user confirmed the built-in microphone is intended; unmuting and a physical capture check await the explicit response. This observation is not proof of the cause of the earlier report.

## Alias cleanup — 2026-11-24

The client asks only for models the key allows: `voice-transcribe` for ASR (Kepler `:9000`) and `qwen3.8-flash-next` for contextual rewrite (Orion `:8080`, now served by Strata on Qwen3.8-Flash-Next Q2_0 at 120k context, two slots). The dedicated `voice-rewrite` alias was removed from the IaC and `whisper-pt-br` is no longer requested, so the earlier key-scope mismatch that forced local fallback is gone. The key stays scoped to `voice-transcribe` and `qwen3.8-flash-next`, and only the former is typed `no-log`. Local fallback is unchanged: Parakeet for ASR and the loopback Ollama model for rewriting.

## Live alias contact, mic order and capture repair — 2026-11-28

Measured against the running gateway and the Endeavour host. Live `/v1/models` and `/key/info` agree on exactly three aliases: `whisper-pt-br`, `parakeet-tdt-v3`, `qwen3.8-flash-next`. Main now asks `whisper-pt-br` for ASR (PR #583) and `qwen3.8-flash-next` for rewrite; the IaC `voice-transcribe` alias remains unapplied and is no longer requested. The deployed Endeavour store copy predates #583, so until the next activation it still requests `voice-transcribe` and `voice-rewrite` and takes the HTTP 403 local fallback.

NoiseTorch stays the dictation and call source. Its autobind now chooses the hardware microphone by explicit order in `modules/desktop/noisetorch-mic.jq`: Hollyland wireless, then Focusrite Scarlett 2i2, then the built-in analog mic, then the highest `priority.session`. Before this change PipeWire priority alone could hand dictation to a newly plugged interface. The RNNoise filter and its 95% VAD threshold are unchanged. The built-in source measured at 0.10 volume while the wireless source measured at 1.00; neither level is qualified for recognition quality.

Two capture defects are repaired. The worker publishes `$XDG_RUNTIME_DIR/voice-dictation/ready` only after installing its SIGUSR1 handler and taking the capture lock. A second shortcut press before that point now stops the unit instead of signalling a process whose default SIGUSR1 disposition would kill it and trip the start limit. The local transcriber fallback parses from the `Processing` line and an optional VAD line, so an extra warning before the banner no longer discards a valid transcript.

Evidence: seven microphone-priority tests, 16 gateway tests, 16 controller tests, two wire tests, Alejandra formatting, and Nix evaluation of the Endeavour autobind service passed. The live journal earlier showed `HTTP 403`, `Local transcriber did not produce a valid result`, and `status=10/USR1` followed by `start-limit-hit`; this change addresses those paths but no physical microphone capture or keypress was exercised.

Multilingual probes through the gateway used synthetic espeak audio and are not a recognition claim. `whisper-pt-br` returned usable Portuguese and perfect English in 0.8–2.2 seconds; `parakeet-tdt-v3` was worse on the Portuguese sample and ignores `language` and `prompt` on this server. `qwen3.8-flash-next` rewrote the mixed Portuguese/English request in 0.9–1.1 seconds, preserving `Az CLI`, `Spark Connect`, `prod`, `tá`, and `sem alterar nada`, with zero reasoning tokens under `reasoning_effort: none`. No glossary prompt is shipped because no human-speech measurement supports it yet. Qualify a glossary with 10–20 recorded multilingual utterances before enabling one.
