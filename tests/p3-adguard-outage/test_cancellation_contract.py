import pathlib
import re
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


def section(source, name, next_name):
    return source[source.index(f"{name}()") : source.index(f"{next_name}()")]


class CancellationAndRecoveryDeadlineContract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()

    def test_worker_traps_reap_the_active_timeout_child(self):
        matrix = section(self.source, "check_dns_matrix", "cancel_workers")
        failures = []
        if not re.search(r"active_(?:probe|timeout)_(?:pid|child)", matrix):
            failures.append("active-timeout-child-pid")
        if not re.search(r"trap[^\n]+(?:TERM|INT)", matrix):
            failures.append("worker-signal-trap")
        if not re.search(r"kill[^\n]+active_(?:probe|timeout)", matrix):
            failures.append("kill-active-timeout-child")
        if not re.search(r"wait[^\n]+active_(?:probe|timeout)", matrix):
            failures.append("wait-active-timeout-child")
        self.assertEqual(failures, [])

    def test_parent_cancel_has_no_delayed_descendant_before_recovery(self):
        cancellation = section(self.source, "worker_cleanup", "run_outage_workers")
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            marker = root / "descendant-fired"; recovery = root / "recovery-started"
            descendant_pid = root / "descendant.pid"; evidence = root / "worker.rows"
            command = r'''
marker=$1; recovery=$2; descendant_pid=$3; evidence=$4; worker_pids=()
check_dns_matrix(){
  printf '01:01:stable\n' >"$evidence"
  sh -c 'trap '\''kill "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 143'\'' TERM INT; (sleep 0.20; : >"$1") & child=$!; echo "$child" >"$2"; wait "$child"' chain "$marker" "$descendant_pid" &
  active_timeout_pid=$!
  wait "$active_timeout_pid"
}
''' + cancellation + r'''
(worker_entry) & worker_pids+=("$!")
worker_pid=${worker_pids[0]}
sleep 0.03
before=$(sha256sum "$evidence")
cancel_workers
after=$(sha256sum "$evidence"); descendant=$(cat "$descendant_pid")
: >"$recovery"
sleep 0.30
[ -e "$recovery" ] && [ ! -e "$marker" ] && [ "$before" = "$after" ] &&
  ! kill -0 "$worker_pid" 2>/dev/null && ! kill -0 "$descendant" 2>/dev/null
'''
            result = subprocess.run(
                ["bash", "-c", command, "contract", str(marker), str(recovery), str(descendant_pid), str(evidence)],
                text=True, capture_output=True, timeout=2,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_parent_never_signals_its_own_process_group(self):
        cancel = section(self.source, "cancel_workers", "run_outage_workers")
        self.assertNotRegex(cancel, r"kill\s+(?:--\s+)?-\$\$|kill\s+0|kill\s+--\s+-\$\{?BASHPID")
        self.assertNotRegex(cancel, r"pkill\s+.*(?:-P\s+\$\$|-g\s+0)")

    def test_every_blocking_recovery_operation_uses_one_absolute_deadline(self):
        recovery = self.source[self.source.index("recover() {") : self.source.index("trap recover EXIT INT TERM")]
        operational = section(self.source, "restored_operational_checks", "exporter_metrics_ready")
        identity = section(self.source, "postrestore_identity", "restored_operational_checks")
        failures = []
        if recovery.count("recovery_deadline=") != 1:
            failures.append("single-recovery-deadline")
        if not re.search(r"(?:deadline_duration|recovery_capture)[^\n]+\$observer|timeout[^\n]+\$observer", identity):
            failures.append("observer-deadline")
        checks = (
            ("postrestore-matrix-deadline", r"append_postrestore_matrix[^\n]+recovery_deadline"),
            ("getent-deadline", r"(?:timeout|recovery_run)[^\n]+getent"),
            ("filter-dig-deadline", r"deadline_duration[^\n]+recovery_deadline[\s\S]{0,250}doubleclick"),
            ("remote-curl-deadline", r"(?:timeout|recovery_run)[^\n]+(?:remote|ssh_command)[^\n]+curl"),
            ("final-dig-deadline", r"deadline_duration[^\n]+recovery_deadline[\s\S]{0,250}k8s\.pastelariadev\.com"),
        )
        for label, pattern in checks:
            if not re.search(pattern, operational):
                failures.append(label)
        if "exporter_metrics_ready \"$recovery_deadline\"" not in operational:
            failures.append("exporter-deadline")
        self.assertEqual(failures, [])

    def test_expired_recovery_budget_exits_promptly(self):
        deadline = section(self.source, "deadline_duration", "check_dns_matrix")
        timeout_helper = section(self.source, "timeout_duration", "deadline_duration")
        command = timeout_helper + deadline + r'''
recovery_deadline=$(($(date +%s%3N)-1))
if deadline_duration "$recovery_deadline" >/dev/null;then exit 90;fi
'''
        started = time.monotonic()
        result = subprocess.run(["bash", "-c", command], text=True, capture_output=True, timeout=1)
        self.assertNotEqual(result.returncode, 90, result.stderr)
        self.assertLess(time.monotonic() - started, 0.5)

    def test_slow_recovery_operations_share_one_ceiling_and_exit_with_artifact_marker(self):
        helpers = self.source[self.source.index("timeout_duration()") : self.source.index("check_dns_matrix()")]
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory) / "failure-artifact"
            command = helpers + r'''
run_dir=$1; marker=$2; recovery_deadline=$(($(date +%s%3N)+250))
recovery_capture sh -c 'sleep 0.05; printf observer' || exit 91
[ "$REPLY" = observer ] || exit 92
if recovery_run sh -c 'sleep 1';then exit 93;fi
: >"$marker"
'''
            started = time.monotonic()
            result = subprocess.run(["bash", "-c", command, "contract", directory, str(marker)],
                text=True, capture_output=True, timeout=1)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(marker.exists())
            self.assertLess(time.monotonic() - started, 0.6)

    def test_recovery_sleeps_are_capped_by_remaining_deadline(self):
        self.assertIn("deadline_sleep()", self.source)
        exporter = section(self.source, "exporter_metrics_ready", "freeze_outage_evidence")
        recovery = self.source[self.source.index("recover() {") : self.source.index("postrestore_operational(){")]
        self.assertNotIn("sleep 1", exporter + recovery)
        self.assertIn("deadline_sleep", exporter); self.assertIn("deadline_sleep", recovery)
        helpers = self.source[self.source.index("timeout_duration()") : self.source.index("check_dns_matrix()")]
        command = helpers + r'''
recovery_deadline=$(($(date +%s%3N)+120))
deadline_sleep "$recovery_deadline" 1000 || exit 91
if deadline_sleep "$recovery_deadline" 1000;then exit 92;fi
'''
        started = time.monotonic(); result = subprocess.run(["bash", "-c", command], text=True, capture_output=True, timeout=1)
        elapsed = time.monotonic() - started
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreater(elapsed, 0.08); self.assertLess(elapsed, 0.35)


if __name__ == "__main__":
    unittest.main()
