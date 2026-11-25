#!/usr/bin/env python3
"""Safely eject this Kindle's storage while leaving USB connected."""

import json
import subprocess


def main():
    listing = subprocess.run(
        ["lsblk", "--json", "--tree", "--bytes", "--output",
         "PATH,TYPE,TRAN,SERIAL,SIZE,MOUNTPOINTS"],
        check=True, capture_output=True, text=True,
    )
    for drive in json.loads(listing.stdout)["blockdevices"]:
        if (drive["type"] != "disk" or drive["tran"] != "usb"
                or drive["serial"] != "90D42201420401EB" or not drive["size"]):
            continue
        for volume in [drive, *drive.get("children", [])]:
            if any(volume.get("mountpoints") or []):
                subprocess.run(
                    ["udisksctl", "unmount", "--block-device", volume["path"],
                     "--no-user-interaction"], check=True,
                )
        subprocess.run([
            "busctl", "--system", "call", "org.freedesktop.UDisks2",
            "/org/freedesktop/UDisks2/drives/Kindle_Internal_Storage_90D42201420401EB",
            "org.freedesktop.UDisks2.Drive", "Eject", "a{sv}", "1",
            "auth.no_user_interaction", "b", "true",
        ], check=True)
        print("Kindle storage safely ejected.", flush=True)


if __name__ == "__main__":
    main()
