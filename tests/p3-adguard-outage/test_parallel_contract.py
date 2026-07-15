import pathlib
import re
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


class ParallelProbeContract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()

    def test_outage_matrix_is_six_deterministic_parallel_workers(self):
        """The stopped gate launches system/RDNSS/Kepler x UDP/TCP concurrently."""
        function = self.source[self.source.index("run_outage_workers()") : self.source.index("append_postrestore_matrix()")]
        outage = self.source[self.source.index("record stopped-gate passed") :]
        proof = function + outage[: outage.index("record secondary-matrix passed")]
        failures = []
        for token in (
            "worker_pids",
            "worker_files",
            "outage-worker-$worker_ordinal",
            "chmod 0600",
            "wait",
        ):
            if token not in proof:
                failures.append(token)
        if 'resolvers=(system system "$rdnss" "$rdnss" 192.168.10.230 192.168.10.230)' not in proof:
            failures.append("canonical-resolver-order")
        if "transports=(udp tcp udp tcp udp tcp)" not in proof:
            failures.append("canonical-transport-order")
        if "for worker_ordinal in 01 02 03 04 05 06" not in function or "worker_pids+=(\"$!\")" not in function:
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
        if not re.search(r"(wc -l|length).*36|36.*(wc -l|length)", self.source, re.S):
            failures.append("six-workers-times-six-rows")
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
        attempts = re.search(r"for attempt in ([^;]+);do", warmup)
        self.assertIsNotNone(attempts)
        count = len(attempts.group(1).split())
        self.assertGreater(count, 5)
        self.assertLess(count, 30)
        self.assertNotRegex(warmup, r"docker (?:start|stop|restart)")
        self.assertLessEqual(count, 29)

    def test_never_ready_recovery_has_one_absolute_ninety_second_ceiling(self):
        recover = self.source[
            self.source.index("recover() {") : self.source.index("postrestore_operational(){")
        ]
        failures = []
        if "recovery_deadline" not in recover:
            failures.append("absolute-recovery-deadline")
        if not re.search(r"90000|90(?:s|\b)", recover):
            failures.append("ninety-second-ceiling")
        if not re.search(r"exporter_metrics_ready[^\n]*recovery_deadline|recovery_deadline[^\n]*exporter_metrics_ready", recover):
            failures.append("exporter-shares-recovery-deadline")
        self.assertEqual(failures, [])

    def test_all_exporter_families_are_validated_from_the_same_response(self):
        warmup = self.source[
            self.source.index("exporter_metrics_ready()") : self.source.index("freeze_outage_evidence()")
        ]
        self.assertEqual(warmup.count("metrics=$("), 1)
        for family in (
            "adguard_queries",
            "adguard_queries_blocked",
            "adguard_avg_processing_time_seconds",
        ):
            self.assertIn(family, warmup)

    def test_later_readiness_cannot_erase_original_failure(self):
        recover = self.source[self.source.index("recover() {") : self.source.index("postrestore_operational(){")]
        self.assertIn("original_failure_rc=$original", recover)
        self.assertNotRegex(recover, r"original(?:_failure_rc)?=0")
        self.assertNotIn('$ok && [ "$original" -eq 0 ]', recover)


if __name__ == "__main__":
    unittest.main()
