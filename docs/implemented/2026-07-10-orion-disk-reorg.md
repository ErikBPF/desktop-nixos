---
title: Orion disk reorg — risk-aligned Steam/models/projects split + /projects on btrfs
status: Implemented (2026-07-10)
date: 2026-07-10
audience: Maintainers of desktop-nixos (+ ha-agent for the /scratch→/projects path change)
post-read-action: Flip orionGpu.profile back to "inference" after LoRA runs; drop the /scratch→/projects symlink once no consumer references /scratch.
---

# Orion disk reorg — risk-aligned split + /projects on btrfs

> **Implemented 2026-07-10:** orion's SanDisk (sdb) `/scratch` was 96% full (Steam
> 293G). Freed space (dropped BlackMythWukong 140G + a duplicate `google/gemma-4-E2B-it`
> HF copy), then **re-laid the two SATA SSDs by disk health**: the older/weaker Kingston
> (sda, ~42k power-on hrs) now carries the **re-downloadable** data (Steam + GGUF models),
> the healthier SanDisk (sdb) carries the **valuable** project/ML work, renamed
> `/scratch`→**`/projects`** and reformatted **ext4→btrfs** (snapper snapshots + autoScrub +
> zstd). Config in `modules/hosts/orion/{hardware.nix,jovian.nix}`; ha-agent run docs
> repointed. No model-serving downtime.

## Why

`/scratch` (SanDisk sdb) hit 96%. Beyond the immediate cleanup, SMART showed the two
SATA SSDs were assigned backwards for durability: the **Kingston SV300S37A** is ~4.8 years
powered-on (42k hrs, old SandForce) yet held nothing precious, while the **healthier
SanDisk SSD Plus** (~2.5 yr, 7 stable reallocated sectors) held the Steam library. The
guiding rule adopted: **disposable/re-downloadable data on the weakest disk; valuable
data on the healthier disk.**

## What shipped

| Disk | Mount | Holds | Rationale |
|------|-------|-------|-----------|
| Kingston sda | `/opt/models` | Steam library (`/opt/models/Steam`, bind→`~/.local/share/Steam`) **+** GGUF models | both re-downloadable; failure = re-fetch, not data loss |
| SanDisk sdb | **`/projects`** (was `/scratch`) | hf cache, ha-agent, venvs, training scripts | valuable ML work on the healthier disk |
| nvme | `/`, `/home` (btrfs) | OS + home | unchanged |

- **Models stayed at `/opt/models`** → servarr `MODELS_PATH` unchanged → **zero llama-chat
  downtime**. Only Steam (154G) moved (Kingston had room); the swap's downtime was Steam-only.
- **`/scratch`→`/projects`**: disko `mountpoint` change + a `L+ /scratch → /projects`
  tmpfiles symlink for back-compat (ha-agent `HF_HOME` and ad-hoc scripts still resolve).
- **sdb ext4→btrfs**: subvol `projects`, `compress=zstd` (97G logical → **63G on-disk**),
  `snapper` config `projects` (mirrors the fleet `/home` config in
  `modules/services/btrfs-snapshots.nix`) + `.snapshots` subvol, covered by the existing
  `services.btrfs.autoScrub`. Migration was nvme-staged and **byte-verified** (103837028848
  bytes / 97018 files identical) before the mkfs; a post-migration baseline snapshot is in place.
- **ha-agent** run docs (`RUN-orion.md`, `RUNBOOK-corpus-and-train.md`) repointed
  `/scratch`→`/projects` (leaf-repo commit `dff883e`, local-only); historical
  `round-1-findings.md` mentions left as past-tense records.

## Verification

- Live + **across a reboot**: `/projects` mounts btrfs cold, `/scratch` symlink resolves,
  all data present, Steam library visible via the Kingston bind, llama-chat healthy, no
  failed units (bar the unrelated `microvm@lander`).
- Baseline `snapper -c projects` snapshot created; `snapper-timeline.timer` armed.

## Gotchas (for next time)

- **disko in NixOS module mode only mounts — it never reformats a live disk.** The
  ext4→btrfs change required a manual `mkfs.btrfs` + subvol create + remount; the disko
  edit only makes the generated `fileSystems` entry match. Deploy the config only after
  the partition is already btrfs, else the switch tries to mount btrfs on ext4 and fails.
- **The mount rename/reformat needs Steam stopped** — Jovian's fhsenv bwrap binds every
  top-level dir (incl. `/scratch`/`/projects`), pinning the mount. Stop `display-manager`
  first; the fhsenv auto-adapts to the new dir name (not hardcoded).
- **Restore-to-SanDisk is slow**: DRAM-less TLC write cliff (770→56 MB/s once the SLC
  cache drains) compounded by btrfs CoW small-file metadata on the venv swarm — ~10 min
  for ~90G. One-time migration cost; reads are unaffected.
- **orion deploy-rs flakes on its confirm-timeout** (rolls back the profile symlink while
  the activation actually took) — recover with a plain `just deploy orion <ip> 2222`
  (`nixos-rebuild switch`, no magic-rollback) to make the new gen sticky.
- **`microvm@lander` fails** (no KVM — orion BIOS SVM disabled) → orion `switch` exits 4;
  false-fatal, unrelated to this work.

## Open

- Flip `orionGpu.profile` back to `"inference"` after the current LoRA training window.
- Drop the `/scratch`→`/projects` symlink once no consumer references `/scratch`.
