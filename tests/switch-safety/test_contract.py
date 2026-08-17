from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).parents[2]


class SwitchSafetyTests(unittest.TestCase):
    def test_live_switch_preserves_boot_blessing_and_telstar_capture(self):
        boot = (ROOT / "modules/hardware/systemd-boot-counting.nix").read_text()
        bless = boot.split("systemd.services.systemd-bless-boot", 1)[1]
        self.assertIn("restartIfChanged = false;", bless)
        self.assertIn("stopIfChanged = false;", bless)
        self.assertIn("systemd-bless-boot status", bless)

        telstar = (ROOT / "modules/hosts/discovery/telstar-capture.nix").read_text()
        capture = telstar.split("systemd.services.telstar-capture", 1)[1]
        self.assertIn("restartIfChanged = false;", capture)
        self.assertIn("stopIfChanged = false;", capture)

    def test_klipper_accepts_large_gcode_uploads(self):
        module = (ROOT / "modules/services/klipper-host.nix").read_text()
        self.assertIn('services.nginx.clientMaxBodySize = "1024m";', module)

    def test_voyager_rollback_preflight_is_console_only_and_generation_bound(self):
        result = subprocess.run(
            ["just", "--dry-run", "voyager-rollback-preflight"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        recipe = result.stdout + result.stderr
        for required in (
            'die() { echo "BLOCKED: $*" >&2; exit 2; }',
            'test "$(hostname)" = voyager',
            "test -c /dev/ttyS0",
            "serial-getty@ttyS0.service",
            "sudo -n true",
            "passwd -S erik",
            "system-([1-9][0-9]*)-link",
            'readlink -f /run/current-system)" = "$(readlink -f "/nix/var/nix/profiles/system-$generation-link',
            "--switch-generation $generation",
            "&& sudo /nix/var/nix/profiles/system-$generation-link/bin/switch-to-configuration switch",
            "(cd machines && just check-stack voyager offsite)",
            "every required container is running/healthy",
            "Voyager console recovery preflight failed",
        ):
            self.assertIn(required, recipe)
        self.assertNotIn("deploy-rs voyager", recipe)
        self.assertNotIn("systemctl reboot", recipe)
