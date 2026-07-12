# Recovery: frozen PID1 after a systemd-bumping `switch`

**Status:** Reference — as-built recovery tape (2026-07-12)

Emergency runbook. If you are reading this at 3am with a dead laptop, skip to
**Do this**.

## Symptom

A `nixos-rebuild switch` that bumps systemd itself triggers a live
`systemctl daemon-reexec` of PID1. On systemd 261 this **froze PID1** on the
laptop (2026-07-12): the desktop kept its last frame, but

- the network went dead (no SSH in),
- `sudo reboot` / `systemctl reboot` **hung forever** — they ask the frozen PID1
  to orchestrate the shutdown, and it never answers,
- nothing on the machine could bring it down cleanly.

Servers on the same bump survived — it is **intermittent**, so treat any
systemd-bumping switch on a fragile host (laptop WiFi/USB-eth, archinaut) as
capable of hitting this. It could hit orion (builder/cache) next time.

## Do this

1. **Try magic SysRq first (cleaner than yanking power).** Hold **Alt** + the
   **SysRq/PrintScreen** key and tap, a second apart:
   **S** (sync disks) → **U** (remount read-only) → **B** (reboot).
   This syncs and unmounts at the *kernel* level, below the frozen PID1, so it is
   a clean reboot even when userspace is wedged. (Mnemonic: the tail of *REISUB*.)
2. **If SysRq does nothing** (kernel also unresponsive, or SysRq disabled):
   **force power-off is safe.** Hold the physical power button ~10 s until it
   cuts, then power back on. **Do not keep waiting for `sudo reboot`** — it will
   never return against a frozen PID1.

## Why the force power-off is safe here

The root filesystems on this fleet are **btrfs on LUKS** — copy-on-write. A
CoW filesystem never overwrites live data in place: a cut power leaves the last
committed tree intact and simply discards the in-flight (not-yet-committed)
transaction. There is no fsck-the-world risk and no half-written superblock.

Verified on the 2026-07-12 incident: after the forced power-off the laptop
booted straight into the previous generation with **zero filesystem corruption**
(`btrfs` mounted clean, no scrub errors). The pending switch was simply lost —
re-run it.

Caveat: this covers the **btrfs/LUKS root**. It does not license yanking power
during a known heavy write to a *different* store (a ZFS resilver, a database
mid-write, a `dd` to a raw disk). Those have their own integrity stories — if one
is in flight, prefer SysRq S+U first.

## After it comes back up

- Confirm the generation: `nixos-rebuild list-generations` / check you booted the
  intended one; the frozen switch did **not** activate, so you are on the prior
  generation.
- `systemctl --failed` should be empty (or only the documented false-fatals).
- Only then re-attempt the upgrade — and on a fragile host, do it with
  **`nixos-rebuild boot` + reboot**, not `switch`: a clean boot of the new
  systemd works; only the *live re-exec* froze. See
  `memory/feedback_never_restart_unprompted` and the per-host activation policy
  in `../proposals/2026-07-12-fleet-upgrade-contract.md` (P4) once it lands.

## Prevention (the real fix)

`boot`+reboot on fragile hosts dodges the live re-exec entirely — that is P4's
per-host activation policy in the fleet-upgrade-hardening RFC
(`../proposals/2026-07-12-fleet-upgrade-hardening.md`). This tape is the net for
when it happens anyway.
