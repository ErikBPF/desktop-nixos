# Voice routing through LiteLLM — deployed with rewrite fallback

**Stage / revision:** RV / 4
**Status:** Orion ASR and Endeavour gateway-first capture deployed; remote rewrite degraded.
**Owner / date:** desktop-nixos, Servarr, homelab-iac / 2026-11-21

## Outcome and why

Human seed: “lets try to move voice stack to use our litellm instance and first path and local models as fallback. We can deploy models on orion and route them via litellm”. Endeavour now tries the homelab gateway for transcription and contextual rewriting, with local Parakeet and Ollama fallback. Super+U dictates; Super+I snapshots copied context and rewrites the spoken instruction; Super+Ctrl+I cancels. Output is copied, never automatically pasted. URLs are not fetched.

## Changes and boundaries

IaC created `voice-transcribe`, `voice-rewrite` and a key restricted to those aliases. OpenBao holds the runtime secret; Endeavour caches it in a mode-0600 file outside the Nix store. The sanctioned Sops bootstrap credential applied only the two voice policy paths, preserving the existing Cloudflare read permission. The normal AppRole then wrote the KV value; it still cannot edit its own policy. No paid-cloud route was added.

Servarr PR363 merged with the explicitly approved merge-commit exception. Its temporary repository merge setting was restored to squash-only. Orion pins the isolated artifact `f991f2cfe84bfd43f14aa47c147439704ebcfa79`, excluding the unrelated backlog. CPU Whisper large-v3-turbo runs in the independent voice stack. Discovery reaches its health endpoint; direct Endeavour access is denied. Isolation depends on both host firewall and Tailscale policy.

The client sends a closed private WAV and reuses it on eligible fallback. Silence and cancellation do not trigger fallback. Invalid results preserve the clipboard; audio is removed on every terminal path. Gateway retries and fallback are disabled, TLS verified, redirects rejected. Endeavour received only the tested voice units and three bindings; unrelated live Hyprland settings were preserved. The prior local generation remains rooted for recovery.

## Evidence and limits

27 unit tests, six existing IaC key contracts, Compose checks, Nix lint/format, Home Manager build and host dry-builds passed. Installed E2E passed synthetic capture through the real controller and services: primary ASR, contextual rewrite fallback, forced local ASR/rewrite, clipboard persistence, cancellation and temporary-audio cleanup. An isolated headless Wayland clipboard protected the user's selection. Plain mode took 10.39 seconds; contextual mode 16.91 seconds; forced local mode 5.99 seconds. Physical microphone and hardware keypress behavior remain untested.

Direct gateway English and Portuguese ASR passed in 14.4 and 12.43 seconds. Orion's existing GPU rewrite remained stuck loading after one owner-managed restart; no GPU reset or reboot was attempted. Scheduled Podman healthchecks report a conmon exec-pidfile failure affecting multiple existing containers; actual ASR health and inference pass. Container health metadata is therefore not green.

Both aliases have typed `no-log=true`; key metadata disables normal prompt storage. A synthetic failed rewrite had one identifiable accounting row and no content marker in recent rows. Successful ASR had no identifiable accounting row, and Langfuse queries timed out. These observations do not prove universal content exclusion, especially diagnostic errors. Only synthetic speech/context was used for qualification.

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
