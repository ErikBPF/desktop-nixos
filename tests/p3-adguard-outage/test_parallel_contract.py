import pathlib
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


class ParallelProbeContract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()

    def test_outage_matrix_separates_four_required_and_two_diagnostic_workers(self):
        function = self.source[self.source.index("run_outage_workers()") : self.source.index("append_postrestore_matrix()")]
        outage = self.source[self.source.index("record stopped-gate passed") :]
        proof = function + outage[: outage.index("record failover-probe passed")]
        failures = []
        for token in (
            "worker_pids",
            "worker_files",
            "core-worker-$worker_ordinal",
            "diagnostic-worker-$worker_ordinal",
            "chmod 0600",
            "wait",
        ):
            if token not in proof:
                failures.append(token)
        if "core_resolvers=(system system 192.168.10.230 192.168.10.230)" not in proof:
            failures.append("canonical-resolver-order")
        if "core_transports=(udp tcp udp tcp)" not in proof or 'diagnostic_resolvers=("$rdnss" "$rdnss")' not in proof:
            failures.append("canonical-transport-order")
        if "for worker_ordinal in 01 02 03 04" not in function or "for worker_ordinal in 01 02" not in function:
            failures.append("six-background-workers")
        self.assertEqual(failures, [])

    def test_workers_share_absolute_deadline_and_use_remaining_dig_timeout(self):
        function = self.source[
            self.source.index("check_dns_matrix()") : self.source.index("postrestore_identity()")
        ]
        failures = []
        if "outage_deadline" not in function:
            failures.append("absolute-deadline")
        if not re.search(r"remaining", function):
            failures.append("remaining-budget")
        if re.search(r"dig .*\+time=2", function):
            failures.append("fixed-dig-timeout")
        if "10000" not in self.source and "10" not in function:
            failures.append("ten-second-cap")
        self.assertEqual(failures, [])

    def test_millisecond_budget_uses_real_gnu_timeout_fractional_seconds(self):
        self.assertIn("timeout_duration()", self.source)
        lines = self.source.splitlines()
        start = next(index for index, line in enumerate(lines) if line.startswith("timeout_duration()"))
        end = next(index for index in range(start + 1, len(lines)) if lines[index] == "}")
        function = "\n".join(lines[start:end + 1])
        command = function + """
duration=$(timeout_duration 150)
[ "$duration" = 0.150s ]
timeout "$duration" sh -c 'exit 0'
if timeout "$duration" sh -c 'sleep 1';then exit 90;else [ "$?" -eq 124 ];fi
"""
        result = subprocess.run(["bash", "-c", command], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_worker_outputs_are_canonical_complete_and_hash_bound(self):
        failures = []
        for token in (
            "partial_outage_results_sha256",
            "worker_ordinal",
            "sort",
            "sha256sum",
        ):
            if token not in self.source:
                failures.append(token)
        if not re.search(r"(wc -l|length).*24|24.*(wc -l|length)", self.source, re.S):
            failures.append("four-required-workers-times-six-rows")
        if "diagnostic_evidence_rows" not in self.source:
            failures.append("diagnostic-row-count")
        self.assertEqual(failures, [])

    def test_failure_deadline_and_signals_cancel_and_reap_every_worker(self):
        failures = []
        for token in ("cancel_workers", "kill", "wait"):
            if token not in self.source:
                failures.append(token)
        if not re.search(r"trap .*recover.*INT", self.source):
            failures.append("sigint-recovery")
        if not re.search(r"cancel_workers.*recover|recover.*cancel_workers", self.source, re.S):
            failures.append("cancel-before-recovery")
        self.assertEqual(failures, [])

    def test_exporter_warmup_is_bounded_beyond_five_seconds_without_container_cycle(self):
        warmup = self.source[
            self.source.index("exporter_metrics_ready()") : self.source.index("freeze_outage_evidence()")
        ]
        self.assertIn("for attempt in {1..60};do", warmup)
        self.assertIn("now+60000", warmup)
        self.assertNotRegex(warmup, r"docker (?:start|stop|restart)")

    def test_never_ready_recovery_has_one_absolute_120_second_ceiling(self):
        recover = self.source[
            self.source.index("recover() {") : self.source.index("postrestore_operational(){")
        ]
        failures = []
        if "recovery_deadline" not in recover:
            failures.append("absolute-recovery-deadline")
        if "120000" not in recover:
            failures.append("120-second-ceiling")
        if not re.search(r"exporter_metrics_ready[^\n]*recovery_deadline|recovery_deadline[^\n]*exporter_metrics_ready", recover):
            failures.append("exporter-shares-recovery-deadline")
        if recover.count("recovery_deadline=$(($(date +%s%3N)+120000))") != 1:
            failures.append("single-recovery-budget")
        if "9618/metrics" in recover or "approved_exporter_ip" in recover:
            failures.append("direct-exporter-ip")
        operational = self.source[
            self.source.index("restored_operational_checks()") : self.source.index("exporter_metrics_ready()")
        ]
        if 'exporter_metrics_ready "$recovery_deadline"' not in operational:
            failures.append("postrestore-shares-remaining-budget")
        self.assertEqual(failures, [])

    def test_fake_clock_enforces_global_120_second_hard_stop(self):
        helpers = self.source[
            self.source.index("timeout_duration()") : self.source.index("check_dns_matrix()")
        ]
        command = helpers + r'''
clock=119999
date(){ printf %s "$clock"; }
recovery_deadline=120000
[ "$(deadline_duration "$recovery_deadline")" = 0.001s ]
clock=120000
if deadline_duration "$recovery_deadline";then exit 90;fi
'''
        result = subprocess.run(["bash", "-c", command], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_exporter_families_are_validated_from_the_same_response(self):
        warmup = self.source[
            self.source.index("exporter_metrics_ready()") : self.source.index("freeze_outage_evidence()")
        ]
        self.assertEqual(
            warmup.count('"sudo -n discovery-stateful-adguard-inventory exporter-families"'),
            1,
        )
        self.assertIn('output=$(<"$capture_file")', warmup)
        self.assertIn('[ "$output" = "$expected" ]', warmup)
        for family in (
            "adguard_queries",
            "adguard_queries_blocked",
            "adguard_avg_processing_time_seconds",
        ):
            self.assertIn(family, warmup)

    def test_split_family_responses_cannot_combine_into_readiness(self):
        warmup = self.source[
            self.source.index("exporter_metrics_ready()") : self.source.index("freeze_outage_evidence()")
        ]
        with tempfile.TemporaryDirectory() as directory:
            counter = pathlib.Path(directory) / "attempts"
            script = warmup + textwrap.dedent(
                f"""
                run_dir={directory}; ssh_command=(fixture_ssh); printf 0 >{counter}
                timeout_duration() {{ printf 2s; }}
                deadline_sleep() {{ return 0; }}
                timeout() {{ shift; "$@"; }}
                fixture_ssh() {{
                  n=$(<{counter}); n=$((n+1)); printf %s "$n" >{counter}
                  if [ $((n % 2)) -eq 1 ];then
                    printf 'adguard_avg_processing_time_seconds=true\nadguard_queries=true\nrequired_family_count=2\n'
                  else
                    printf 'adguard_queries_blocked=true\nrequired_family_count=1\n'
                  fi
                }}
                if exporter_metrics_ready $(($(date +%s%3N)+120000));then exit 90;fi
                [ "$(<{counter})" -eq 60 ]
                """
            )
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_later_readiness_cannot_erase_original_failure(self):
        recover = self.source[self.source.index("recover() {") : self.source.index("postrestore_operational(){")]
        self.assertIn("original_failure_rc=$original", recover)
        self.assertNotRegex(recover, r"original(?:_failure_rc)?=0")
        self.assertNotIn('$ok && [ "$original" -eq 0 ]', recover)


if __name__ == "__main__":
    unittest.main()
