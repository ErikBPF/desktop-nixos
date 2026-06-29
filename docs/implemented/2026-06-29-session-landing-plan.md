---
title: Landing plan — get the 2026-06-28/29 session work onto main
status: Done (2026-06-29)
date: 2026-06-29
audience: Maintainers of desktop-nixos + servarr + homelab-iac
post-read-action: Land each repo's outstanding work to main (leaf-first), tick the boxes, then move this plan to done.
---

# Landing plan — session work → main

This session deployed/applied a lot that isn't all committed to `main` yet,
across three repos. Definition of **done**: every box below is checked (all
deployed/applied changes are committed + pushed to `main`, nothing live diverges
from git). When done, this plan graduates to `docs/implemented/` (or is deleted
per the docs policy — it's an execution checklist).

Order = coupling map (leaf repos first, then the desktop-nixos hub).

## Security note (resolved, no fix needed)
Audited: **no plaintext secret is git-visible.** swag-dns01 is encrypted in
homelab-iac MinIO state + servarr `.env.sops`; the tracked Harbor
`common/config/*/env` files have **empty** secret values (injected at runtime);
the decrypted `.env` is untracked. The "Harbor leak" flag was a false alarm.

## 1. servarr (leaf) — `git@…/servarr`

Already on main (this session): SWAG image re-pin `5.6.0-ls467`, `.env.sops`
swag-dns01 token.

- [x] **loki.yml + monitoring.yml** — landed on main (`f55e9c4`, telemetry §5).
- [x] hermes `SOUL.md`/`config.yaml` — also landed (`0fc97e7`, by the hermes owner).
- [x] Verify: working tree clean, in sync with origin.

## 2. homelab-iac (leaf) — `git@…/homelab-iac`

All **applied** to Cloudflare already; git source must catch up or
`homelab-iac-drift` will flag state≠source.

- [x] **dns + swag-token + api-token** — landed on main (`d1aa937`), in sync.
- [x] Verify: working tree clean (cache ignored); 0/0 vs origin.

## 3. desktop-nixos (hub)

Most of the docs reorg + diagnostics already committed earlier. Remaining:

- [x] doc status/reference edits + new docs (dendritic-contract, cloudflare-token
  migration, discovery-resilience, this plan) committed + pushed.
- [x] `justfile` (docs-check/structure-check), `CLAUDE.md`,
  `modules/hosts/discovery/harbor.nix` (deployed) committed + pushed.
- [x] Excluded `hyprland.nix`, `desktop.nix`, the brazil proposal (not this session).
- [x] Verify: `docs-check` + `structure-check` + `fmt-check` + `lint` green.

## 4. Close-out

- [x] cloudflare-token migration RFC §6 swag-dns01 phase marked done;
  telemetry-hardening already in `implemented/`.
- [x] **Plan moved to done** — graduated to `docs/implemented/`, README index
  updated, `docs-check` green.

## Not in scope (tracked elsewhere)
- The resilience fixes (deploy-pipeline rsync/git conflict, compose project-name
  drift, DNS self-dependency, cert monitoring) live in
  [`2026-06-29-discovery-resilience-fixes.md`](../proposals/2026-06-29-discovery-resilience-fixes.md)
  — landing *that work* is a separate effort; this plan only lands the **commits**
  already made/deployed this session.
