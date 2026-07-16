import copy
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

from test_inventory import raw


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/hosts/discovery/_stateful-adguard-postcheck.py"


def load():
    spec = importlib.util.spec_from_file_location("adguard_postcheck", SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LogRunner:
    def __init__(self, logs): self.logs = logs; self.calls = []
    def run(self, argv):
        self.calls.append(argv)
        if argv[1] == "inspect": return "2026-07-16T00:00:00Z\n"
        return self.logs[argv[-1]]


class PostcheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.m = load()

    def test_startup_scan_exact_allowlists_counts_only_and_retains_no_logs(self):
        runner = LogRunner({"adguard": "ready\n", "adguard-exporter": "listening\n"})
        result = self.m.startup_fatal_log_scan(
            "adguard,adguard-exporter", "container-start", "counts-only",
            "|".join(self.m.FATAL_LOG_PATTERNS), runner,
        )
        self.assertEqual(result, {"containers":["adguard","adguard-exporter"],"fatal_matches":{"adguard":0,"adguard-exporter":0},"patterns_checked":len(self.m.FATAL_LOG_PATTERNS),"raw_logs_retained":False,"status":"passed","version":1})
        self.assertEqual([call[0:2] for call in runner.calls], [["docker","inspect"],["docker","logs"],["docker","inspect"],["docker","logs"]])
        self.assertNotIn("ready", json.dumps(result)); self.assertNotIn("listening", json.dumps(result))
        for field,value in (("containers","exporter,adguard"),("since","all"),("output","raw"),("patterns","fatal")):
            arguments={"containers":"adguard,adguard-exporter","since":"container-start","output":"counts-only","patterns":"|".join(self.m.FATAL_LOG_PATTERNS)};arguments[field]=value
            with self.assertRaises(self.m.ContractError): self.m.startup_fatal_log_scan(arguments["containers"],arguments["since"],arguments["output"],arguments["patterns"],runner)

    def test_startup_scan_fatal_result_is_value_free_and_not_passed(self):
        runner=LogRunner({"adguard":"credential=value\nFATAL startup stopped\n","adguard-exporter":"ok\n"})
        result=self.m.startup_fatal_log_scan("adguard,adguard-exporter","container-start","counts-only","|".join(self.m.FATAL_LOG_PATTERNS),runner)
        self.assertEqual(result["fatal_matches"],{"adguard":1,"adguard-exporter":0});self.assertEqual(result["status"],"fatal");self.assertFalse(result["raw_logs_retained"]);self.assertNotIn("credential",json.dumps(result));self.assertNotIn("value",json.dumps(result))

    def inventory(self):
        value=raw();value["containers"][0]["Id"]="8"*64;value["containers"][1]["Id"]="9"*64
        # Normalize through the production inventory helper's public contract.
        inventory_source=ROOT/"modules/hosts/discovery/_stateful-adguard-inventory.py";spec=importlib.util.spec_from_file_location("inventory_for_postcheck",inventory_source);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module.normalize(value)

    def test_stable_observation_captures_31_samples_and_returns_only_normalized_edges(self):
        inventory=self.inventory();captures=[];sleeps=[];now=[0]
        def capture(): captures.append(True); return copy.deepcopy(inventory)
        def sleep(seconds):sleeps.append(seconds);now[0]+=seconds
        result=self.m.stable_observation("adguard,adguard-exporter",900,30,"full-normalized-start-end","exact-new-and-stable","exact","zero","discard",capture=capture,sleep=sleep,clock=lambda:now[0])
        self.assertEqual(len(captures),31);self.assertEqual(sleeps,[30]*30);self.assertEqual(result["duration_seconds"],900);self.assertEqual(result["sample_interval_seconds"],30);self.assertEqual(result["samples"],31);self.assertEqual(result["start"],result["end"]);self.assertFalse(result["raw_logs_retained"]);self.assertEqual(set(result["start"]),{"baseline","containers"});self.assertNotIn("query_sample_count",json.dumps(result))

    def test_stable_observation_rejects_identity_health_restart_and_baseline_drift(self):
        base=self.inventory()
        mutations=(lambda value:value["containers"][0].update(restart_count=1),lambda value:value["containers"][0].update(health="unhealthy"),lambda value:value["containers"][0].update(id="7"*64),lambda value:value["baseline"]["api"].update(filter_count=value["baseline"]["api"]["filter_count"]+1))
        for mutate in mutations:
            calls=0
            def capture():
                nonlocal calls
                calls+=1;value=copy.deepcopy(base)
                if calls==2:mutate(value)
                return value
            with self.subTest(mutate=mutate),self.assertRaises(self.m.ContractError):self.m.stable_observation("adguard,adguard-exporter",900,30,"full-normalized-start-end","exact-new-and-stable","exact","zero","discard",capture=capture,sleep=lambda _:None)

    def test_cli_invalid_contract_reports_class_only(self):
        result=subprocess.run([sys.executable,SOURCE,"startup-fatal-log-scan","--containers","wrong","--since","container-start","--output","counts-only","--fatal-patterns","fatal"],text=True,capture_output=True)
        self.assertEqual(result.returncode,1);self.assertEqual(result.stdout,"");self.assertEqual(result.stderr,"discovery-stateful-adguard-postcheck: BLOCKED: ContractError\n")


if __name__ == "__main__": unittest.main()
