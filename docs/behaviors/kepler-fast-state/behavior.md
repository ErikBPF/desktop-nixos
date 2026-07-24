# Kepler fast state

**Status:** Implemented

Move reproducible AI working data and k3s microVM images off the OS Btrfs disk
onto dedicated `fast-pool` ZFS datasets. Preserve existing AI paths, require the
fast pool before guests start, retain source copies until cluster verification,
then remove only the verified old copies.
