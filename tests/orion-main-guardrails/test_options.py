"""Check Orion's merged recovery policy without builds or activation.

Run: python3 -B tests/orion-main-guardrails/test_options.py
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
BASELINE = "f2d020432580f8ca30d23f917c4053e2e20054d5"
OPTIONS = """c: {
  sysctl = c.boot.kernel.sysctl;
  kernelParams = c.boot.kernelParams;
  wol = {
    inherit (c.systemd.services.orion-wol) enable wantedBy after serviceConfig;
  };
  builder = {
    inherit (c.systemd.services.nix-cache-builder) enable serviceConfig environment;
  };
  cacheTimerEnabled = c.systemd.timers.nix-cache-builder.enable;
  generatedTimerEnabled = c.systemd.units."nix-cache-builder.timer".enable;
  cacheTimer = {
    inherit (c.systemd.timers.nix-cache-builder) wantedBy timerConfig;
  };
  suppressedUnits = c.systemd.suppressedSystemUnits;
  preserved = {
    kernel = c.boot.kernelPackages.kernel.outPath;
    kernelParams = c.boot.kernelParams;
    cacheBuildScript = c.systemd.services.nix-cache-builder.script;
    cacheServing = {
      inherit (c.services.nix-serve) enable bindAddress port secretKeyFile;
      package = c.services.nix-serve.package.outPath;
    };
    wol = {
      inherit (c.systemd.services.orion-wol) enable wantedBy after serviceConfig;
    };
    sleepTargets = builtins.mapAttrs (_: target: target.enable) {
      inherit (c.systemd.targets) sleep suspend hibernate hybrid-sleep;
    };
    login = c.services.logind.settings.Login;
    autoUpgrade = {
      inherit (c.system.autoUpgrade) enable flake operation flags allowReboot dates;
    };
  };
}"""


def evaluate(flake):
    return json.loads(subprocess.check_output(
        ["nix", "eval", "--json", flake + "#nixosConfigurations.orion.config",
         "--no-write-lock-file", "--builders", "", "--max-jobs", "0",
         "--option", "allow-import-from-derivation", "false",
         "--option", "substituters",
         "https://cache.nixos.org https://nix-community.cachix.org https://hyprland.cachix.org",
         "--option", "extra-substituters", "", "--apply", OPTIONS],
        cwd=ROOT, text=True,
    ))


class OrionMainGuardrailsOptions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline = evaluate("git+" + ROOT.as_uri() + "?rev=" + BASELINE)
        cls.options = evaluate(".")

    def test_oops_and_detected_cpu_lockups_reboot_after_ten_seconds(self):
        for name, value in {
            "kernel.panic": 10,
            "kernel.panic_on_oops": 1,
            "kernel.watchdog": 1,
            "kernel.nmi_watchdog": 1,
            "kernel.softlockup_panic": 1,
            "kernel.hardlockup_panic": 1,
            "kernel.watchdog_thresh": 30,
        }.items():
            with self.subTest(sysctl=name):
                self.assertEqual(self.options["sysctl"].get(name), value)
        self.assertEqual(
            [p for p in self.options["kernelParams"] if p.startswith("panic=")],
            ["panic=10"],
        )

    def test_existing_wol_sleep_and_main_configuration_are_preserved(self):
        wol = self.options["wol"]
        self.assertTrue(wol["enable"])
        self.assertIn("multi-user.target", wol["wantedBy"])
        self.assertEqual(wol["serviceConfig"]["Type"], "oneshot")
        self.assertTrue(wol["serviceConfig"]["RemainAfterExit"])
        self.assertTrue(wol["serviceConfig"]["ExecStart"].endswith(
            "/bin/ethtool -s enp4s0 wol g"
        ))
        preserved = self.options["preserved"]
        for name, value in self.baseline["preserved"].items():
            with self.subTest(preserved=name):
                self.assertEqual(preserved[name], value)
        for name, enabled in preserved["sleepTargets"].items():
            with self.subTest(target=name):
                self.assertFalse(enabled)
        for name in ("IdleAction", "HandleSuspendKey", "HandleHibernateKey",
                     "HandleLidSwitch", "HandleLidSwitchExternalPower"):
            with self.subTest(logind=name):
                self.assertEqual(preserved["login"][name], "ignore")

    def test_cache_build_has_native_resource_and_cancellation_bounds(self):
        builder = self.options["builder"]
        self.assertTrue(builder["enable"])
        self.assertEqual(builder["serviceConfig"]["Type"], "oneshot")
        for name, value in {
            "CPUQuota": "400%",
            "TimeoutStartSec": "89min",
            "TimeoutStopSec": "1min",
            "KillMode": "control-group",
            "SendSIGKILL": True,
        }.items():
            with self.subTest(property=name):
                self.assertEqual(builder["serviceConfig"].get(name), value)
        settings = builder["environment"].get("NIX_CONFIG", "").splitlines()
        for name in ("max-jobs", "cores"):
            with self.subTest(nix_setting=name):
                values = [line.split("=", 1)[1].strip() for line in settings
                          if "=" in line and line.split("=", 1)[0].strip() == name]
                self.assertTrue(values)
                self.assertEqual(set(values), {"2"})

    def test_scheduled_and_catch_up_builds_are_restored(self):
        self.assertNotIn("nix-cache-builder.timer", self.options["suppressedUnits"])
        with self.subTest(timer="configured"):
            self.assertTrue(self.options["cacheTimerEnabled"])
        with self.subTest(timer="generated"):
            self.assertTrue(self.options["generatedTimerEnabled"])
        timer = self.options["cacheTimer"]
        self.assertIn("timers.target", timer["wantedBy"])
        self.assertEqual(timer["timerConfig"]["OnCalendar"], "03:00")
        self.assertTrue(timer["timerConfig"]["Persistent"])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(OrionMainGuardrailsOptions)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.testsRun and result.wasSuccessful():
        print("ORION_MAIN_GUARDRAILS_OK")
    else:
        raise SystemExit(1)
