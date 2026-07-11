# archinaut microSD failure — recovery + reflash hardening

**Status:** ✅ IMPLEMENTED (2026-07-10) · **Host:** `archinaut` (RPi 3B+ Klipper host) · **Date:** 2026-07-10

> **Outcome.** archinaut's microSD died ~2.5 weeks after flashing. Root cause was
> not the SD "just wearing out" — a fleet-wide **atuin sync server** dragged
> PostgreSQL onto the 1 GB Pi, where it crash-looped and hammered the card.
> Fixed the cause, added a Pi-sized log shipper so failures stay diagnosable,
> reflashed onto a new card, and closed the gaps that made the reflash painful.
> Printer is live again; logs ship to Loki. Related record:
> [`2026-06-20-archinaut-kernel-direct-boot.md`](2026-06-20-archinaut-kernel-direct-boot.md),
> [`2026-06-16-printer-nixos-host.md`](2026-06-16-printer-nixos-host.md).

## What failed

The Pi went dark. Post-mortem off the card's own (persistent) journal showed the
SD controller timing out with read I/O errors at a fixed region (~10.4 GB), and
every service `start operation timed out` behind it — including NetworkManager,
so the WiFi-only host fell off the network. Confirmed on a healthy USB reader:
reads at that region abort after 30–40 s (`Sense Key: Aborted Command`). Dead
NAND, not power or config.

The **~2.5-week** lifetime was the tell — far too short for normal wear. Cause:

- `profile-base` imported `m.nixos.atuin` **fleet-wide**, which enables
  `services.atuin` — the atuin **sync server**, which pulls in **PostgreSQL**.
- The atuin **client** (`home.atuin`) runs `auto_sync = false`, so the server had
  **zero clients** — dead weight on every host. On the 1 GB archinaut it
  crash-looped postgres (`restart counter at 8`), and a crash loop writes to the
  journal + WAL continuously. Combined with nightly `autoUpgrade` closure writes
  and persistent journald, that wore the consumer microSD out in weeks.

## What shipped

Fleet + host config (`desktop-nixos`):

- **Drop the unused atuin server fleet-wide** — removed `m.nixos.atuin` from
  `modules/profiles/base.nix`. Client history is untouched; postgres is gone from
  every host (verified `services.postgresql.enable == false` on archinaut and
  kepler). *(commit `9e047f6`)*
- **`vector-logs` — a lite journal→Loki shipper** (`modules/services/vector-logs.nix`,
  `flake.modules.nixos.vector-logs`). Vector idles at ~30–60 MB vs Alloy's
  ~260 MB (Alloy starved sshd on boot on this Pi — see
  [`2026-06-20-telemetry-hardening.md`](2026-06-20-telemetry-hardening.md)). It
  matches Alloy's label schema (`{source="journal", host=…}`) so archinaut shows
  up in the fleet Logs dashboard. Imported by archinaut. *(commit `9e047f6`)*
- **Keep journald persistent** on archinaut (`services.journald.storage =
  "persistent"`) — the on-card journal is exactly what made this post-mortem
  possible; with the crash-loop gone the capped 50 M journal writes little.
  *(commit `9e047f6`)*
- **Weekly autoUpgrade** on archinaut (`dates = "Wed 05:00"`, was nightly) —
  cuts full-closure microSD writes ~7×. *(commit `9e047f6`)*
- **autoUpgrade over `git+https`, fleet-wide** — all hosts used
  `flake = "github:ErikBPF/desktop-nixos#<host>"`; the `github:` fetcher resolves
  through `api.github.com`, anon-rate-limited to **60 req/hr per IP**. The whole
  fleet shares one home NAT IP, so upgrade checks exhausted the budget and
  `nixos-upgrade` failed with **HTTP 403** (the home IP was 60/60 used).
  `git+https://github.com/ErikBPF/desktop-nixos?ref=main#<host>` fetches over git
  smart-HTTP — not the API, no such limit, no auth needed (public repo).
  *(commit `42be7f2`)* See also `memory/just_upgrade_gotchas` for the manual
  `just upgrade` path (access-token workaround).
- **Parallel aarch64 builds on orion** — the sdImage built serially on one of
  orion's 32 cores: orion was registered `x86_64-linux`-only in `buildMachines`,
  so the `build-archinaut-sd` recipe's `--builders` override omitted the maxjobs
  field (nix defaults to 1). Added `aarch64-linux` to orion's persistent builder
  (`modules/services/distributed-builds.nix`, maxJobs=16) and `maxjobs=16` to the
  recipe's inline spec. *(commit `65913e7`)*

Network (`homelab-iac`) — tailnet ACL grant so vector can reach Loki:

- Added `archinaut` to the `hosts` map and the `discovery:3100,9090`
  observability-sink accept rule (`tailscale/acl/policy.hujson`). *(commits
  `8686952`, then `7c1b1c6` after the reflash changed the tailnet IP.)*

## Reflash runbook

The **how** lives in `justfile` recipes; if a recipe and this doc disagree, the
recipe wins.

1. **Build** the aarch64 SD image on orion: `just build-archinaut-sd` →
   `result-archinaut-sd/sd-image/*.img.zst`.
2. **Flash + seed the sops key in one step**: `just flash-archinaut-sd /dev/sdX`.
   This dd's the image *and* injects the age key (see gotcha 1) so WiFi comes up
   on first boot. *(recipe added commit `5bcec14`.)*
3. Insert the card, **power the printer**, boot.
4. **Restore printer config**: `just seed-archinaut` (rsyncs `klipper-biqu`
   `printer_data/config/` → `/var/lib/klipper`, restarts klipper/moonraker).
5. Verify: SSH `erik@192.168.10.225:2222`, `systemctl is-active klipper moonraker
   vector`, Mainsail at `http://192.168.10.225`, and `{host="archinaut"}` logs in
   Grafana/Loki.

## Reflash gotchas (why the SD path bit us)

1. **sops age key is not in the SD image.** The WiFi PSK is a sops secret
   decrypted at boot via `sops.age.keyFile = /home/erik/.config/sops/age/keys.txt`,
   staged by `first-boot` from `/var/lib/sops-staging/age-keys.txt`. Only the
   nixos-anywhere/provision path seeded that (via `--extra-files`); the plain
   sdImage doesn't. A freshly-flashed card boots with no key → sops can't decrypt
   the PSK → WiFi never comes up → the WiFi-only Pi is unreachable. **Fixed:**
   `just flash-archinaut-sd` now injects the key post-flash (secret stays out of
   the `.img`). `secrets/sops/secrets.yaml` is encrypted to `[*primary,
   *archinaut]`, so the laptop's primary key decrypts it.
2. **Reflash mints a new tailnet identity.** The Pi enrolls as a **new node with
   a new tailnet IP** (old node goes stale). The `homelab-iac` ACL `hosts` map
   entry for `archinaut` must be updated to the new IP or the `discovery:3100`
   log-ship grant won't match. (Future option: persist `/var/lib/tailscale` for a
   stable identity.) First-boot `tailscaled-autoconnect` also races the authkey
   decrypt / DNS-ready — if it fails, `systemctl restart tailscaled-autoconnect`
   once DNS + NTP settle.
3. **The printer MCU must be powered.** klipper `mcu 'mcu': Serial connection
   closed` on `/dev/ttyS1` means the mainboard MCU is off/desynced. Power the
   printer, then `curl -X POST http://192.168.10.225:7125/printer/firmware_restart`.
   (The rp2040 USB device is the BTT Eddy probe, a *secondary* MCU — the main MCU
   is the GPIO mini-UART.)

## Durable follow-ups (not yet done)

- **High-endurance / industrial microSD, or USB-SSD boot** (the Pi 3 supports it)
  — the real longevity fix beyond reducing writes.
- **Persist `/var/lib/tailscale`** so a reflash keeps the same tailnet IP and
  skips the ACL bump.
