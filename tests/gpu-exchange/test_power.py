"""Run the production per-device script against a fake nvidia-smi."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "modules/hosts/apollo/_gpu-power.sh"


class GPUPower(unittest.TestCase):
    def test_inventory_and_independent_device_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            smi = root / "nvidia-smi"
            smi.write_text("""#!/bin/sh
case "$1" in
  --query-gpu=*)
    [ "$QUERY_FAIL" = 0 ] || exit 1
    printf '%s\\n' "$INVENTORY"
    ;;
  *)
    printf '%s\\n' "$*" >> "$CALLS"
    [ "$FAIL_GPU" != "$1" ] || exit 1
    case "$*" in *--reset-gpu-clocks*) [ "$FAIL_CLOCK" = 0 ] || exit 1 ;; esac
    ;;
esac
""")
            smi.chmod(0o755)
            old = "GPU-old, 0x248810DE"
            new = "GPU-new, 0x2D0410DE"
            cases = [
                ("three-reordered", new + "\n" + old + "\nGPU-new2, 0x2D0410DE", "", "0", 0, 6),
                ("3070-only", old, "", "0", 0, 2),
                ("one-failure-does-not-skip-others", new + "\n" + old, "--id=GPU-new", "0", 1, 3),
                ("unknown-device", "GPU-unknown, 0xFFFF10DE\n" + old, "", "0", 1, 2),
                ("no-devices", "", "", "0", 1, 0),
                ("query-failure", old, "", "1", 1, 0),
                ("clock-failure", old + "\n" + new, "", "0", 1, 4),
            ]
            for name, inventory, failed, query_fail, status, count in cases:
                with self.subTest(name=name):
                    log = root / "calls"
                    log.write_text("")
                    env = dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"],
                               INVENTORY=inventory, FAIL_GPU=failed, QUERY_FAIL=query_fail, CALLS=str(log),
                               FAIL_CLOCK="1" if name == "clock-failure" else "0")
                    result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, status, result.stderr)
                    calls = log.read_text().splitlines()
                    self.assertEqual(len(calls), count, calls)
                    if status == 0:
                        for gpu, watts in (("GPU-old", 170), ("GPU-new", 145), ("GPU-new2", 145)):
                            if gpu + "," in inventory:
                                self.assertEqual(
                                    [call for call in calls if call.startswith(f"--id={gpu} ")],
                                    [f"--id={gpu} --error-on-warning --power-limit={watts}",
                                     f"--id={gpu} --error-on-warning --reset-gpu-clocks"])
                    for call in calls:
                        self.assertIn("--error-on-warning", call)
                        if call.startswith("--id=GPU-old "):
                            self.assertTrue(call.endswith("--power-limit=170") or
                                            call.endswith("--reset-gpu-clocks"), call)
                        else:
                            self.assertTrue(call.startswith(("--id=GPU-new ", "--id=GPU-new2 ")), call)
                            self.assertTrue(call.endswith("--power-limit=145") or
                                            call.endswith("--reset-gpu-clocks"), call)


if __name__ == "__main__":
    unittest.main()
