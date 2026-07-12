# RFC: Fleet ESP enlargement (512M → 2G) via staged reinstall

**Status:** Draft — 2026-07-12 — reinstalls **gated behind explicit approval**

> Spun out of `docs/proposals/2026-07-12-fleet-upgrade-hardening.md` P3. That
> RFC's decision: enlarge the ESP fleet-wide, accepting a full re-format, rather
> than band-aid with shrink-initrd / `configurationLimit=1`. The **config-size
> bump landed already** (commit bumping `ESP.size` `"512M"`→`"2G"` in every
> disko-managed host's `hardware.nix`); it takes effect **only** on a fresh disko
> install, so running hosts are untouched. This RFC covers the **destructive
> second half** — migrating the *existing* hosts to the roomy ESP, which is a
> per-host reinstall. **Do not execute any step here without explicit per-host
> approval in the turn.**

## Why

Every disko-managed host's ESP was 512M. With ~180–200M initrds (kepler 180M,
discovery ~199M once nvidia GSP firmware is in) and `configurationLimit=2`, a
nixpkgs bump was one large initrd away from overflowing the ESP on every deploy
(systemd-boot writes the new generation before pruning the old). kepler only fit
the 2026-07-12 bump by reclaiming ~207M of stale GRUB debris — a one-time win.
2G gives ≥8× today's initrd, room for `configurationLimit` head-room, and
survives a doubled initrd. See `memory/kepler_kvm_boot_constraints`,
`memory/fleet_upgrade_2026_07_12` #2.

## Target layout

- **ESP:** `2G`, `vfat`, `type = EF00`, `mountpoint = /boot` (unchanged except size).
- **Root:** the remaining `100%` — unchanged per host (btrfs / LUKS+btrfs / btrfs
  RAID1). The 1.5G the ESP grows by comes out of the front of the root
  partition; no other partition changes.
- **Data disks / pools:** left exactly as they are **only where they are not in
  the host's disko config** — see the audit below, because for one host they
  *are*.

## Data-preservation audit (READ FIRST — the premise "disko wipes only the boot
disk" is FALSE for orion)

`nixos-anywhere` runs the host's **full** `diskoScript`, which formats **every
disk declared in `disko.devices`** — not just the one holding the ESP. So the
survival question is per-disk: *is this disk in the disko config?* If yes → it is
wiped. If it is a pre-existing mount (`fileSystems.*` only) or an imperative pool
→ it survives.

| Host | disko wipes | Survives (not in disko) | Notes / pre-reinstall action |
|------|-------------|-------------------------|------------------------------|
| **kepler** | OS M.2 only (`disk.os`, Toshiba 256G) | ZFS `fast-pool` (4× Kingston SSD) → `/fast`; future `bulk-pool` → `/bulk`. Pools are **imperative**, explicitly *not* in disko. | Safest host. `/home/erik` (root subvol) is wiped → servarr clone re-pulls. Confirm `zpool import fast-pool` after reinstall; sanoid snapshots live in the pool → survive. |
| **discovery** | `sda` (ESP + RAID1 root half) **and** `sdc` (RAID1 mirror) | `sdb` (Seagate 3.6T HDD, `LABEL=vault` → `/home/erik/vault`): all docker volumes, media, HAOS QCOW2. Not in disko. | **Hub / crown jewel — last.** `/home/erik/homelab/apps/*` (netbird pocket-id, hermes datadirs, netbird GeoIP) and `/home/erik/servarr` are on the **root `/home` subvol → WIPED**. netbird accounts/peers live in the **postgres** container (volume on `sdb`) → survive **iff** Docker data-root is on `sdb` — **verify `docker info | grep "Docker Root Dir"` points at `sdb` before wiping.** Re-provision pocket-id/hermes datadirs (GeoIP re-downloads). |
| **orion** | **all three disks**: `nvme0` (ESP+root), `sda` (`/opt/models`), `sdb` (`/projects`) | **nothing** — every disk is in disko | ⚠️ **Highest risk.** A naive `just deploy-orion` **destroys `/projects` (ML / ha-agent) and `/opt/models` (Steam + GGUF).** Two safe options: (a) **scope disko to the boot disk only** (partition `nvme0` by hand / a boot-disk-only disko invocation, leave `sda`/`sdb` mounted); or (b) back up `/projects` first (`/opt/models` is re-downloadable per `memory/orion_disk_layout`) then let the full disko run and restore. Prefer (a). Builder/cache host → **last with discovery.** |
| **laptop** | single disk (ESP + LUKS + btrfs root) | — | Full `/home` wipe. Data is largely syncthing/git/cloud, but treat as a clean install: back up `/home/erik` (or confirm syncthing is 100% converged) first. **This is the machine work is driven from** — reinstall needs another host or a live-USB to run `nixos-anywhere` against it; cannot self-reinstall while running. |
| **pathfinder** | single disk (ESP + LUKS + btrfs root) | — | Secondary workstation, currently on an old rev anyway. Low stakes — good early canary. |
| **telstar** | OS disk | — | OCI guest, `profile-oci-guest`, effectively stateless. Cloud reinstall. Good first canary to validate the 2G layout end-to-end. |

**Not in scope (no disko ESP to enlarge):** voyager and vanguard use Oracle's
fixed pre-partitioned `/boot/efi` (`fileSystems`, not disko — cannot be resized
by us); archinaut (RPi 3B+) is SD-card kernel-direct boot, no ESP.

**Crown-jewel backup gate (all hosts, before its reinstall):** restic-snapshot
the host's config/state to the voyager off-site anchor
(`memory/voyager_offsite_dr_anchor`) and confirm the snapshot lists, *before*
wiping. For discovery this includes the postgres dumps + `/home/erik/homelab`
app state; for orion, `/projects`.

## Staged reinstall order (least-critical first; hub + builder last)

1. **telstar** — stateless OCI canary. Validates the 2G disko layout + boot end
   to end with nothing to lose.
2. **pathfinder** — secondary workstation on an old rev; low stakes, second canary.
3. **laptop** — after syncthing-converged / `/home` backup; driven from another
   host or live-USB (cannot self-reinstall).
4. **kepler** — schedule around an AI-serving window (LiteLLM / voice backend).
   Safest data-wise (ZFS pools survive); still a serving outage during reinstall.
5. **orion** — builder/cache + the 3-disk data hazard. Use the boot-disk-scoped
   disko path (audit option a) or back up `/projects` first. Warm the binary
   cache expectations: while orion is down the fleet loses its substituter.
6. **discovery** — hub / crown jewel, **last**. Everything else depends on it
   (Vault, Prometheus/Grafana, SWAG ingress, netbird control plane, Loki). Verify
   `sdb` survival plan (Docker data-root) first; expect to re-provision
   `/home/erik/homelab` app datadirs and re-pull the servarr clone after.

Never more than one host in flight. Verify boot + services on host *N* before
touching *N+1*.

## Per-host procedure

For each host, in order:

1. **Backup gate.** restic → voyager; confirm the snapshot exists. For orion also
   back up `/projects`; for discovery confirm docker volumes are on `sdb`.
2. **Confirm the config bump is live in the flake.** `ESP.size = "2G"` for the
   host (already committed) — `just dry <host>` clean.
3. **Reinstall.** `just deploy-<host>` (nixos-anywhere wipe+reinstall) — **except
   orion**, where the disko run must be scoped to the boot disk (see audit) so
   `/opt/models` + `/projects` are not formatted.
4. **Restore data.** Re-import ZFS pools (kepler), re-mount `vault` + re-provision
   app datadirs + re-pull servarr (discovery), re-mount `/projects`+`/opt/models`
   (orion), sync `/home` (laptop).
5. **Verify.** `systemctl --failed` empty (or only known false-fatals), the
   host's key services up (`systemctl status` / `journalctl -u` / curl per the
   fleet-upgrade-hardening "Verify changes" rules), and `df -h /boot` shows the
   ~2G ESP. A green rebuild is not proof — check the service.

## Rollback / abort

A reinstall is destructive and has **no in-place rollback** — once disko runs,
the old root is gone. The safety model is therefore *forward-only with a net*:

- **Backup-first + one-at-a-time** (above) is the rollback: if host *N* fails to
  boot or a service won't come up, **stop the fleet migration**, restore *N* from
  its restic snapshot onto a re-run install, and do **not** proceed to *N+1*
  until *N* is green.
- If a reinstall fails mid-run (nixos-anywhere aborts), the host is down until
  re-run; it does not cascade to other hosts because they are untouched. Cloud
  hosts (telstar) can be re-imaged from the provider console; physical hosts need
  a live-USB.
- **Abort criteria:** any host that needs more than one restore attempt, or any
  data disk that comes back unreadable, halts the migration for human review —
  do not "push through" the remaining hosts.

## Open items

- orion boot-disk-scoped disko invocation: decide the exact mechanism (hand
  `sgdisk` + `mkfs` on `nvme0` then `nixos-install`, vs a trimmed disko config)
  and document it before orion's turn.
- discovery Docker data-root confirmation (is it really on `sdb`?) — verify on
  the live host before scheduling.
