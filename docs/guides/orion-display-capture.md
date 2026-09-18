# Orion display wake capture

**Status:** Failure captured; forced HDMI connection configured, pending reboot and TV-cycle verification.

## Persistent HDMI configuration

The September 13, 2026 failure followed display idle/wake while audio continued.
The TTY remained visible, disabling HDR did not restore the picture, and restarting
the display manager recovered the session. No system-suspend event was found.
This narrows the failure to the graphical session/output path but does not prove
a Gamescope-only root cause.

[Orion's Jovian module](../../modules/hosts/orion/jovian.nix) now keeps HDMI-A-1
logically connected with `video=HDMI-A-1:D` and supplies the TV's captured EDID
with `drm.edid_firmware=HDMI-A-1:edid/lg-tv.bin`. NixOS packages the EDID for the
initrd and the running system. The capture has two 128-byte blocks with valid
checksums; it retains the TV's advertised modes, audio and HDR capabilities.
Replace the EDID if the connected display or its advertised capabilities change.

Deploy with `just deploy-rs-boot orion`, then reboot with `just reboot-orion`
when workloads can be interrupted. After reboot, verify both parameters in
`/proc/cmdline` and capture the healthy display. Turn the TV off and on, then
repeat the original idle/wake sequence. Verify that HDMI remains connected and
the picture and audio return without restarting the graphical session.
This is a prevention experiment, not a proven fix until those checks pass.

To undo the experiment, remove the `hardware.display` block and its EDID asset,
deploy the revised configuration for boot, and reboot. The existing system-sleep
inhibition remains independent of this display configuration.

## Capture procedure

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
