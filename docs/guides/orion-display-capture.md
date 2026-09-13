# Orion display wake capture

**Status:** Capture tooling implemented; failure reproduction pending.

Run from the desktop-nixos checkout on the controlling computer:

```bash
just capture-orion-display
```

The command saves a private snapshot in a new `/tmp/orion-display-*/snapshot.txt`
directory on the controlling computer. It reads Orion over SSH without restarting
the session, changing display settings, or deploying a generation. No monitor
is running afterward. Keep the snapshots elsewhere before the local `/tmp` is
cleaned if longer retention is needed.

1. Capture once while the picture works.
2. Let the screen sleep normally, then attempt to wake it with the usual input.
3. If it stays black, run the same command from the controlling computer before
   rebooting, restarting Steam, or unplugging HDMI. Capture within 30 minutes
   of the failure to include the event in the journal window.
4. Note the local time, Gaming Mode versus Hyprland, TV power state, whether
   the TV reports “no signal,” and whether audio/controller input still works.
5. If the picture recovers, capture again and record what restored it.

Each snapshot includes the boot ID, booted/current generation, kernel and
gamescope versions, sessions, connector status/modes, base64 EDID, GPU power
mode, and recent kernel/graphics journals. `CAPTURE_FAILED` marks a failed or
timed-out probe; an SSH failure retains partial output. Hyprland queries are
skipped when it is not running; with multiple instances they query instance 0.
Kernel journal access uses noninteractive sudo. Logs remain private local
evidence and should be reviewed before sharing.

Compare HDMI disconnect/EDID loss with gamescope errors, AMD timeouts/resets,
or an actual system sleep transition. This capture does not establish that
any EDID override or kernel change is needed.

Local collector regression check:

```bash
python scripts/test_capture_orion_display.py
```
