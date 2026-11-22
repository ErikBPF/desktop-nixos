# Local clipboard dictation — historical first slice

**Stage / revision:** FEEDBACK / 3 (initial IP → RED → GREEN → E2E → RV preserved in receipts)
**Status:** F9 prompt correction deployed on Endeavour; reproduced quality regression passed. Confirmation against the user’s original example is pending.
**Owner / date:** desktop-nixos / 2026-11-21

The current gateway-first deployment and shortcuts are documented in the [LiteLLM one-pager](litellm-one-pager.md). The evidence below records the earlier local-only slice.

## Outcome and why

Human seed: “lets start by deploying local models and perfecting the shortcut capture to clipped text flow”. The user confirmed Endeavour and “both modes, copy result without auto-pasting”. Those answers are bound to question `call_c0295b4f01ec45dbb308d00df774b3d4` and this checkout, branch `feat/voice-dictation`.

The desktop now provides local speech-to-clipboard and copied-context rewriting. The broader meeting, Android, activity archive and knowledge-ingestion apps remain future slices. This is working desktop integration, not a claim of perfected recognition or general rewrite accuracy.

## What changed

| Shortcut | Behavior |
|---|---|
| Super+F8 | Start plain dictation; press again to stop and copy. |
| Super+F9 | Snapshot copied text, record dictation, then rewrite locally and copy. |
| Super+F10 | Cancel before clipboard commit; retain existing clipboard. |

Either recording shortcut stops the current recording. Repeated toggles during processing do not start another capture. Notifications show recording, processing and completion. There is no automatic paste or submit.

Voxtype 1.1.1 uses checksum-pinned Parakeet v3 INT8. A separate Ollama service binds only `127.0.0.1:11435`, serving Qwen3.5 4B. Downloaded model digest: `d8b0f5e9760cd1682034f292d7ef72ec46f432149be0df7574bf2d6e92e38c04`. No cloud fallback or automatic model updates are configured.

The controller serializes captures, reads clipboard context only at contextual capture start, keeps that snapshot in memory, and removes its private temporary transcript after processing. Empty, failed and truncated results do not replace the clipboard. The clipboard owner survives the capture service. Voxtype is the sole daemon for its shared runtime namespace; do not independently launch another instance.

## Evidence and limits

- [Thirteen unit tests](receipts/unit-tests.txt) cover context isolation, cancellation, malformed/truncated rewrite responses, failed transcription and detached clipboard ownership. Assertion-failing RED anchors and independent corrections are recorded in the [review receipt](receipts/review.txt); the [first draft](receipts/first-draft.patch) is preserved.
- [Live rewrite fixtures](receipts/rewrite-smoke.txt) passed English commitments, Portuguese and copied-instruction isolation. Warm requests took 8–9 seconds. These three cases do not guarantee arbitrary LLM output.
- [Full controller E2E](receipts/e2e.txt) passed plain capture, contextual capture, clipboard survival after worker exit, cancellation without clipboard modification, and temporary-file cleanup. PipeWire used a verified virtual source. Reported 1.84/9.44-second timings include a deliberate one-second clipboard-persistence check: approximately 0.8/8.4 seconds stop-to-copy.
- English synthetic ASR passed. Robotic Portuguese was poor; neural Portuguese with one second of trailing silence matched the expected sentence. No physical microphone was recorded by the automated checks.
- Nix lint, formatting, documentation links, Endeavour evaluation/build and system dry-build were checked. See [validation](receipts/validation.txt) for final outcomes.

## Deployment and continuing work

Installed only generated voice units and the three Hyprland bindings from `/nix/store/33j86miqkgkvpbir3xfwflzsfgs05njk-home-manager-generation`, rooted at `~/.local/state/voice-dictation/generation`. Full Home Manager activation was avoided because it also changed unrelated OpenCode and desktop configuration. Sources remain uncommitted; a later switch from a branch lacking this feature can remove it.

Both services are enabled and active. Diagnostic and virtual-audio overrides were removed. Capture uses the existing NoiseTorch default microphone. Human feedback: “f9 not working properly”, clarified as “Text appears, but the rewrite is wrong” (question `call_fe346ca81666468085f31e03aefe5a60`). Binding and both services are healthy; recent context workers exited successfully. A sanitized context/dictation/actual/expected example is requested to establish the regression. No clipboard contents were read for diagnosis. A synthetic probe reproduced omission of “sem alterar nada”. The corrected prompt treats dictation as directions for composing text and copied material as reference only. [Assertion RED](receipts/f9-red.txt), rejected first candidate and [four passing live model cases](receipts/f9-green.txt) preserve the repair evidence. The deployed controller matches tested source; both services remain active. Personal-example confirmation remains pending. Personal microphone accuracy remains unqualified.

## Risks and recovery

Review text before pasting: rewriting can change meaning. Existing clipboard history may retain copied inputs/results. There is no transcript archive yet. Cancellation cannot undo a clipboard commit already in progress.

Recovery: stop/disable `voice-transcriber` and `voice-rewrite`, stop any `voice-dictation@plain`/`@context` capture, and restore the previous Hyprland symlink recorded in `~/.local/state/voice-dictation/initial-paths.json`. Remove the feature import before a later declarative deployment. Do not roll back unrelated desktop services.
