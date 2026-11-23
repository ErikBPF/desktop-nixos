# Orion voice host wiring — deployed

**Stage / revision:** RV / 3
**Status:** Independent CPU ASR deployed and inference verified.
**Owner / date:** desktop-nixos / 2026-11-21

The requested LiteLLM-first voice path now uses Orion's independent managed `voice` stack. Servarr owns the workload; desktop-nixos owns activation and the Discovery-source TCP9000 rule using fleet metadata. Tailscale ACL ordering remains part of the isolation boundary. Discovery health returned HTTP200; Endeavour direct access timed out as expected.

Owner recipes pinned Servarr `f991f2cfe84bfd43f14aa47c147439704ebcfa79`, deployed Orion and activated voice. PR363 preserves this artifact's ancestry; unrelated backlog is excluded from the rollout. Host closure: `/nix/store/ddgr64wlk50fd6wywmvchq8wg4vx6zkv-nixos-system-orion-26.11.20261115.5c3cda7`. Preview excluded the unrelated package update before deployment. Lint, format and system dry-build passed.

The CPU Speaches image is digest-pinned, with eight threads, int8 and an 8 GiB memory limit. Cached Whisper model revision is `df99141c9f5db0615d025664cff8949373a69593`; future downloads are not revision-enforced by this API. Gateway English/Portuguese transcription passed in 14.4/12.43 seconds. Installed Endeavour E2E also passed gateway ASR and local fallback.

Scheduled Podman healthchecks fail with conmon exec-pidfile errors across multiple containers, despite passing manual ASR health and inference. Do not claim healthy container metadata. The existing GPU rewrite remained loading after one owner-managed ai-models restart; no repeated restart, GPU reset or reboot occurred. Client fallback covers this degradation; host-runtime repair is outstanding.

Recovery uses the prior NixOS generation and prior Servarr pin `2090849b39b1b1112c0d98580d202ebe6459a10a` through owner recipes. Source publication/integration for host wiring remains pending; the deployed workload artifact is published. OpenBao credentials are applied, not awaiting a handoff.
