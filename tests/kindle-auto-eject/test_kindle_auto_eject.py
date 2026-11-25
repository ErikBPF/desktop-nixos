import copy
import json
from pathlib import Path
import runpy
import subprocess
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "modules/desktop/_kindle-auto-eject.py"
DRIVE = {
    "path": "/dev/sdz", "type": "disk", "tran": "usb",
    "serial": "90D42201420401EB", "size": 1436549120,
    "mountpoints": [None],
    "children": [{"path": "/dev/sdz1", "type": "part", "tran": None,
                  "serial": None, "size": 1436540928,
                  "mountpoints": ["/run/media/erik/Kindle"]}],
}


class KindleAutoEjectTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "Kindle auto-ejection script is missing")
        self.main = runpy.run_path(str(SCRIPT))["main"]
        self.drive = copy.deepcopy(DRIVE)

    def run_script(self, drives, failure=None):
        listing = subprocess.CompletedProcess([], 0, json.dumps({"blockdevices": drives}))
        effects = [listing, failure] if failure else None
        with patch("subprocess.run", return_value=listing, side_effect=effects) as run:
            if failure:
                with self.assertRaises(subprocess.CalledProcessError):
                    self.main()
            else:
                self.main()
        return [call.args[0] for call in run.call_args_list]

    def test_unmounts_before_ejecting_even_if_device_name_changes(self):
        commands = self.run_script([self.drive])
        self.assertEqual(commands[1], ["udisksctl", "unmount", "--block-device",
                                       "/dev/sdz1", "--no-user-interaction"])
        self.assertEqual(commands[2], [
            "busctl", "--system", "call", "org.freedesktop.UDisks2",
            "/org/freedesktop/UDisks2/drives/Kindle_Internal_Storage_90D42201420401EB",
            "org.freedesktop.UDisks2.Drive", "Eject", "a{sv}", "1",
            "auth.no_user_interaction", "b", "true",
        ])
        self.assertEqual(len(commands), 3)

    def test_requests_tree_output_to_find_mounted_partitions(self):
        commands = self.run_script([])
        self.assertIn("--tree", commands[0])

    def test_ignores_other_serials_internal_drives_and_absent_kindle(self):
        other = copy.deepcopy(self.drive)
        other["serial"] = "OTHER"
        internal = copy.deepcopy(self.drive)
        internal["tran"] = "nvme"
        for drives in ([], [other], [internal]):
            with self.subTest(drives=drives):
                self.assertEqual(len(self.run_script(drives)), 1)

    def test_already_ejected_media_is_left_alone(self):
        self.drive["size"] = 0
        self.drive.pop("children")
        self.assertEqual(len(self.run_script([self.drive])), 1)

    def test_unmounted_media_can_still_be_ejected(self):
        self.drive["children"][0]["mountpoints"] = [None]
        commands = self.run_script([self.drive])
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[1][0], "busctl")

    def test_busy_filesystem_stops_ejection(self):
        commands = self.run_script(
            [self.drive], subprocess.CalledProcessError(1, "udisksctl"))
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[-1][0], "udisksctl")


if __name__ == "__main__":
    unittest.main()
