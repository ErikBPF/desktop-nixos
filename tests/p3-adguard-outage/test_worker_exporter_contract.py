import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


def function(source, name, next_name):
    return source[source.index(f"{name}()") : source.index(f"{next_name}()")]


class WorkerExporterContract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()
        self.matrix = function(self.source, "check_dns_matrix", "worker_cleanup")
        self.exporter = function(self.source, "exporter_metrics_ready", "freeze_outage_evidence")

    def run_matrix(self, replies):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            reply_dir = root / "replies"
            reply_dir.mkdir()
            for index, reply in enumerate(replies, 1):
                (reply_dir / str(index)).write_text(reply)
            script = self.matrix + textwrap.dedent(
                f"""
                set -u
                namespace=fixture; enforce_deadline=false
                counter={root}/counter; printf 0 >"$counter"
                timeout_duration() {{ printf '%s' 2s; }}
                deadline_check() {{ return 0; }}
                od() {{ printf ' aa'; }}
                timeout() {{ shift; "$@"; }}
                sudo() {{
                  local n; n=$(<"$counter"); n=$((n+1)); printf %s "$n" >"$counter"
                  cat {reply_dir}/"$n"
                }}
                rows={root}/rows; : >"$rows"
                if check_dns_matrix 04 system tcp "$rows"; then rc=0; else rc=$?; fi
                printf 'RC=%s ROWS=%s\\n' "$rc" "$(wc -l <"$rows")"
                exit "$rc"
                """
            )
            return subprocess.run(["bash", "-c", script], text=True, capture_output=True)

    @staticmethod
    def valid_replies():
        return [
            ";; ->>HEADER<<- status: NOERROR, id: 1\n;; flags; QUERY: 1, ANSWER: 1\nx 1 IN A 192.168.10.210\n",
            ";; ->>HEADER<<- status: NOERROR, id: 2\n;; flags; QUERY: 1, ANSWER: 0\n",
            ";; ->>HEADER<<- status: NOERROR, id: 3\n;; flags; QUERY: 1, ANSWER: 1\nx 1 IN A 1.1.1.1\n",
            ";; ->>HEADER<<- status: NOERROR, id: 4\n;; flags; QUERY: 1, ANSWER: 1\nx 1 IN AAAA 2606:4700::1111\n",
            ";; ->>HEADER<<- status: NXDOMAIN, id: 5\n;; flags; QUERY: 1, ANSWER: 0\n",
            ";; ->>HEADER<<- status: NXDOMAIN, id: 6\n;; flags; QUERY: 1, ANSWER: 0\n",
        ]

    def test_actual_matrix_rejects_ambiguous_or_malformed_dig_contract(self):
        cases = {
            "empty-rc0": "",
            "missing-status": ";; flags; QUERY: 1, ANSWER: 1\nx IN A 192.168.10.210\n",
            "multiple-status": ";; status: NOERROR, id: 1\n;; status: NXDOMAIN, id: 2\n;; ANSWER: 1\n192.168.10.210\n",
            "missing-answer": ";; status: NOERROR, id: 1\n192.168.10.210\n",
            "multiple-answer": ";; status: NOERROR, id: 1\n;; ANSWER: 1\n;; ANSWER: 0\n192.168.10.210\n",
            "nonnumeric-answer": ";; status: NOERROR, id: 1\n;; ANSWER: many\n192.168.10.210\n",
            "wrong-status": ";; status: NXDOMAIN, id: 1\n;; ANSWER: 1\n192.168.10.210\n",
            "wrong-answer-contract": ";; status: NOERROR, id: 1\n;; ANSWER: 0\n",
        }
        for label, bad in cases.items():
            with self.subTest(label=label):
                replies = self.valid_replies()
                replies[0] = bad
                result = self.run_matrix(replies)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_matrix_accepts_both_filter_contracts(self):
        for filtered in (
            ";; status: NXDOMAIN, id: 6\n;; ANSWER: 0\n",
            ";; status: NOERROR, id: 6\n;; ANSWER: 1\nx 1 IN A 0.0.0.0\n",
        ):
            replies = self.valid_replies()
            replies[-1] = filtered
            result = self.run_matrix(replies)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("RC=0 ROWS=6", result.stdout)

    def test_worker04_malformed_sixth_row_freezes_35_partial_rows_only(self):
        contract = self.source
        self.assertIn('partial_outage_results_sha256', contract)
        self.assertIn('if $outage_complete;then frozen_outage_results_sha256=', contract)
        self.assertRegex(contract, r'run_outage_workers\s*\n\[ "\$\(cat .*wc -l\)" -eq 36 \]')
        replies = self.valid_replies()
        replies[-1] = ";; status: NOERROR, id: 6\n;; ANSWER: broken\n"
        result = self.run_matrix(replies)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ROWS=5", result.stdout)

    def test_actual_parallel_workers_are_collision_free_and_canonical_under_stress(self):
        worker_source = self.source[
            self.source.index("check_dns_matrix()") : self.source.index("append_postrestore_matrix()")
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            script = worker_source + textwrap.dedent(
                f"""
                set -u
                run_dir={root}; namespace=fixture; rdnss=fd00::53
                enforce_deadline=true; outage_deadline=$(($(date +%s%3N)+120000))
                timeout_duration() {{ printf 120s; }}
                deadline_check() {{ [ "$(date +%s%3N)" -le "$outage_deadline" ]; }}
                timeout() {{ shift; "$@"; }}
                sudo() {{
                  local name type
                  sleep "0.00$((RANDOM % 9 + 1))"
                  name=${{@: -2:1}}; type=${{@: -1}}
                  case "$name:$type" in
                    *.homelab.pastelariadev.com:A)
                      printf '%s\n' ';; status: NOERROR, id: 1' ';; ANSWER: 1' 'x 1 IN A 192.168.10.210' ;;
                    *.homelab.pastelariadev.com:AAAA)
                      printf '%s\n' ';; status: NOERROR, id: 2' ';; ANSWER: 0' ;;
                    *.1-1-1-1.sslip.io:A)
                      printf '%s\n' ';; status: NOERROR, id: 3' ';; ANSWER: 1' 'x 1 IN A 1.1.1.1' ;;
                    *.2606-4700-4700--1111.sslip.io:AAAA)
                      printf '%s\n' ';; status: NOERROR, id: 4' ';; ANSWER: 1' 'x 1 IN AAAA 2606:4700::1111' ;;
                    *.invalid:A)
                      printf '%s\n' ';; status: NXDOMAIN, id: 5' ';; ANSWER: 0' ;;
                    *.doubleclick.net:A)
                      printf '%s\n' ';; status: NXDOMAIN, id: 6' ';; ANSWER: 0' ;;
                    *) return 90 ;;
                  esac
                }}
                for iteration in $(seq 1 20);do
                  rm -f "$run_dir"/outage-worker-*.rows
                  run_outage_workers || exit 91
                  [ "${{#worker_files[@]}}" -eq 6 ] || exit 92
                  [ "$(printf '%s\n' "${{worker_files[@]}}" | sort -u | wc -l)" -eq 6 ] || exit 93
                  for file in "${{worker_files[@]}}";do
                    [ "$(stat -c %a "$file")" = 600 ] || exit 94
                    [ "$(wc -l <"$file")" -eq 6 ] || exit 95
                  done
                  prefixes=$(cat "${{worker_files[@]}}" | LC_ALL=C sort -t: -k1,1n -k2,2n | cut -d: -f1-2)
                  expected=$(for ordinal in 01 02 03 04 05 06;do for row in 01 02 03 04 05 06;do printf '%s:%s\n' "$ordinal" "$row";done;done)
                  [ "$prefixes" = "$expected" ] || exit 96
                done
                """
            )
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exporter_requires_exact_bound_id_network_and_single_ipv4(self):
        valid = '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.7","GlobalIPv6Address":""}}}}]'
        invalid = {
            "wrong-id": '[{"Id":"' + "b" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.7"}}}}]',
            "missing-network": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{}}}]',
            "extra-network": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.7"},"other":{"IPAddress":"172.21.0.7"}}}}]',
            "multiple-ip": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.7 172.20.0.8"}}}}]',
            "invalid-ip": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"not-an-ip"}}}}]',
            "wrong-family": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"2001:db8::7"}}}}]',
            "changed-valid-runtime-ip": '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.8"}}}}]',
        }
        self.assertEqual(self.run_exporter(valid, ready_after=1).returncode, 0)
        for label, inspect_json in invalid.items():
            with self.subTest(label=label):
                result = self.run_exporter(inspect_json, ready_after=1)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                if label == "changed-valid-runtime-ip":
                    self.assertIn("ATTEMPTS=0", result.stdout)

    def test_exporter_delayed_and_never_ready_paths_are_bounded(self):
        self.assertIn("warmup_deadline", self.exporter)
        self.assertIn("recovery_deadline", self.exporter)
        self.assertIn("return 1", self.exporter)
        self.assertIn("deadline_sleep", self.exporter)
        self.assertNotIn("docker restart", self.exporter)
        delayed = '[{"Id":"' + "a" * 64 + '","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.20.0.7"}}}}]'
        result = self.run_exporter(delayed, ready_after=3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ATTEMPTS=3", result.stdout)
        result = self.run_exporter(delayed, ready_after=999)
        self.assertNotEqual(result.returncode, 0)
        self.assertLessEqual(int(result.stdout.split("ATTEMPTS=")[-1].split()[0]), 29)

    def run_exporter(self, inspect_json, ready_after):
        with tempfile.TemporaryDirectory() as directory:
            counter = pathlib.Path(directory) / "counter"
            script = self.exporter + textwrap.dedent(
                f"""
                exporter_id={'a' * 64}; approved_exporter_ip=172.20.0.7; ssh_command=(fixture_ssh); printf 0 >{counter}
                timeout_duration() {{ printf 2s; }}
                deadline_sleep() {{ return 0; }}
                timeout() {{ shift; "$@"; }}
                fixture_ssh() {{
                  case $* in
                    *'docker inspect'*) printf '%s\\n' '{inspect_json}' ;;
                    *curl*)
                      n=$(<{counter}); n=$((n+1)); printf %s "$n" >{counter}
                      if [ "$n" -ge {ready_after} ];then
                        printf '%s\\n' '# TYPE adguard_queries counter' '# TYPE adguard_queries_blocked counter' '# TYPE adguard_avg_processing_time_seconds gauge'
                      fi ;;
                    *) return 88 ;;
                  esac
                }}
                if exporter_metrics_ready $(($(date +%s%3N)+30000));then rc=0;else rc=$?;fi
                printf 'ATTEMPTS=%s RC=%s\\n' "$(<{counter})" "$rc"
                exit "$rc"
                """
            )
            return subprocess.run(["bash", "-c", script], text=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
