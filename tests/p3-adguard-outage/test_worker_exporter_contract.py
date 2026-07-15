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
                if check_dns_matrix 04 system tcp "$rows" 0123456789abcdef0123456789abcdef; then rc=0; else rc=$?; fi
                printf 'RC=%s ROWS=%s\\n' "$rc" "$(wc -l <"$rows")"
                exit "$rc"
                """
            )
            return subprocess.run(["bash", "-c", script], text=True, capture_output=True)

    @staticmethod
    def valid_replies():
        return [
            ";; ->>HEADER<<- status: NOERROR, id: 1\n;; flags; QUERY: 1, ANSWER: 1\n;; ANSWER SECTION:\nx 1 IN A 192.168.10.210\n",
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

    def test_fleet_a_uses_only_answer_rrs_and_requires_exact_discovery_address(self):
        rejected = (
            # The approved address appears only in the question/comment text.
            ";; status: NOERROR, id: 1\n;; ANSWER: 1\n;; QUESTION SECTION:\n;192.168.10.210.example. IN A\n;; no answer; expected 192.168.10.210\n",
            # One approved and one foreign A answer must not be accepted.
            ";; status: NOERROR, id: 1\n;; ANSWER: 2\n;; ANSWER SECTION:\nx 1 IN A 192.168.10.210\ny 1 IN A 192.168.10.99\n",
        )
        for reply in rejected:
            with self.subTest(reply=reply):
                replies = self.valid_replies()
                replies[0] = reply
                result = self.run_matrix(replies)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

        replies = self.valid_replies()
        replies[0] = (
            ";; status: NOERROR, id: 1\n;; ANSWER: 2\n;; ANSWER SECTION:\n"
            "x 1 IN A 192.168.10.210\ny 1 IN A 192.168.10.210\n"
        )
        result = self.run_matrix(replies)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("RC=0 ROWS=6", result.stdout)

    def test_core_success_is_independent_of_asymmetric_diagnostic_terminal_results(self):
        worker_source = self.source[
            self.source.index("check_dns_matrix()") : self.source.index("append_postrestore_matrix()")
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            script = worker_source + textwrap.dedent(
                f"""
                set -u
                run_dir={root}; namespace=fixture; rdnss=fd00::53; outage_nonce=0123456789abcdef0123456789abcdef
                enforce_deadline=true; outage_deadline=$(($(date +%s%3N)+30000))
                timeout_duration() {{ printf 30s; }}
                deadline_check() {{ return 0; }}
                timeout() {{ shift; "$@"; }}
                sudo() {{
                  local args="$*" name type
                  name=${{@: -2:1}}; type=${{@: -1}}
                  if [[ $args == *'@fd00::53'* && $args == *'+tcp'* ]];then
                    printf '%s\n' 'malformed diagnostic reply'
                    return 0
                  fi
                  [[ $args == *'@fd00::53'* ]] || sleep 0.02
                  case "$name:$type" in
                    *.homelab.pastelariadev.com:A)
                      printf '%s\n' ';; status: NOERROR, id: 1' ';; ANSWER: 1' ';; ANSWER SECTION:' 'x 1 IN A 192.168.10.210' ;;
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
                run_outage_workers; rc=$?
                [ "$rc" -eq 0 ] || exit 91
                [ "$(cat "${{worker_files[@]}}" | wc -l)" -eq 24 ] || exit 92
                [ "${{#diagnostic_terminal_files[@]}}" -eq 2 ] || exit 93
                for terminal in "${{diagnostic_terminal_files[@]}}";do
                  [ "$(stat -c %a "$terminal")" = 600 ] || exit 94
                  jq -e 'keys==["ordinal","rc_class","resolver_label","row_count","status","transport"]' "$terminal" >/dev/null || exit 95
                done
                jq -e '.ordinal==1 and .resolver_label=="gateway-rdnss" and .transport=="udp" and .rc_class=="success" and .status=="complete" and .row_count==6' "${{diagnostic_terminal_files[0]}}" >/dev/null || exit 96
                jq -e '.ordinal==2 and .resolver_label=="gateway-rdnss" and .transport=="tcp" and .rc_class=="failed" and .status=="failed" and .row_count==0' "${{diagnostic_terminal_files[1]}}" >/dev/null || exit 97
                """
            )
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_core_failure_reaps_blocked_diagnostics_and_freezes_two_terminal_records(self):
        worker_source = self.source[
            self.source.index("check_dns_matrix()") : self.source.index("append_postrestore_matrix()")
        ]
        freeze_source = function(self.source, "freeze_outage_evidence", "recover")
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            script = worker_source + freeze_source + textwrap.dedent(
                f"""
                set -u
                run_dir={root}; namespace=fixture; rdnss=fd00::53; outage_nonce=0123456789abcdef0123456789abcdef
                enforce_deadline=true; outage_deadline=$(($(date +%s%3N)+30000)); outage_complete=false
                timeout_duration() {{ printf 30s; }}
                deadline_check() {{ return 0; }}
                timeout() {{ shift; "$@"; }}
                sudo() {{
                  if [[ $* == *'@fd00::53'* ]];then
                    printf '%s\n' "$BASHPID" >>{root}/diagnostic-pids
                    exec sleep 30
                  fi
                  printf '%s\n' 'malformed required-core reply'
                }}
                if run_outage_workers;then exit 91;else rc=$?;fi
                [ "$rc" -ne 0 ] || exit 92
                [ "${{#diagnostic_terminal_files[@]}}" -eq 2 ] || exit 93
                for terminal in "${{diagnostic_terminal_files[@]}}";do
                  [ -s "$terminal" ] || exit 94
                  [ "$(stat -c %a "$terminal")" = 600 ] || exit 95
                  jq -e '.resolver_label=="gateway-rdnss" and .rc_class=="cancelled" and .status=="cancelled" and .row_count==0' "$terminal" >/dev/null || exit 96
                done
                if [ -f {root}/diagnostic-pids ];then
                  while read -r child;do kill -0 "$child" 2>/dev/null && exit 97;done <{root}/diagnostic-pids
                fi
                frozen_outage_results_sha256=;outage_evidence=;diagnostic_evidence=
                freeze_outage_evidence || exit 98
                [ "$diagnostic_evidence_status" = partial ] || exit 99
                [ -n "$partial_diagnostic_results_sha256" ] || exit 100
                """
            )
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_worker04_malformed_sixth_row_keeps_required_core_partial_only(self):
        contract = self.source
        self.assertIn('partial_outage_results_sha256', contract)
        self.assertIn('if $outage_complete&&[ "$core_evidence_rows" -eq 24 ]', contract)
        self.assertRegex(contract, r'run_outage_workers\s*\n\[ "\$\(cat .*wc -l\)" -eq 24 \]')
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
                run_dir={root}; namespace=fixture; rdnss=fd00::53; outage_nonce=0123456789abcdef0123456789abcdef
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
                      printf '%s\n' ';; status: NOERROR, id: 1' ';; ANSWER: 1' ';; ANSWER SECTION:' 'x 1 IN A 192.168.10.210' ;;
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
                  rm -f "$run_dir"/core-worker-*.rows "$run_dir"/diagnostic-worker-*.rows
                  run_outage_workers || exit 91
                  [ "${{#worker_files[@]}}" -eq 4 ] || exit 92
                  [ "$(printf '%s\n' "${{worker_files[@]}}" | sort -u | wc -l)" -eq 4 ] || exit 93
                  for file in "${{worker_files[@]}}";do
                    [ "$(stat -c %a "$file")" = 600 ] || exit 94
                    [ "$(wc -l <"$file")" -eq 6 ] || exit 95
                  done
                  prefixes=$(cat "${{worker_files[@]}}" | LC_ALL=C sort -t: -k1,1n -k2,2n | cut -d: -f1-2)
                  expected=$(for ordinal in 01 02 03 04;do for row in 01 02 03 04 05 06;do printf '%s:%s\n' "$ordinal" "$row";done;done)
                  [ "$prefixes" = "$expected" ] || exit 96
                done
                """
            )
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exporter_requires_exact_canonical_helper_output(self):
        valid = "adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=true\nrequired_family_count=3\n"
        self.assertEqual(self.run_exporter(valid, ready_after=1).returncode, 0)
        invalid = {
            "missing": "adguard_avg_processing_time_seconds=true\nadguard_queries=true\nrequired_family_count=2\n",
            "false": "adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=false\nrequired_family_count=2\n",
            "extra": valid + "unexpected=true\n",
            "reordered": "adguard_queries=true\nadguard_avg_processing_time_seconds=true\nadguard_queries_blocked=true\nrequired_family_count=3\n",
            "wrong-count": valid.replace("count=3", "count=4"),
        }
        for label, output in invalid.items():
            with self.subTest(label=label):
                self.assertNotEqual(self.run_exporter(output, ready_after=1).returncode, 0)
        for mode in ("nonzero", "timeout"):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_exporter(valid, ready_after=1, mode=mode).returncode, 0)

    def test_exporter_delayed_and_never_ready_paths_are_bounded(self):
        self.assertIn("warmup_deadline", self.exporter)
        self.assertIn("recovery_deadline", self.exporter)
        self.assertIn("return 1", self.exporter)
        self.assertIn("deadline_sleep", self.exporter)
        self.assertNotIn("docker restart", self.exporter)
        delayed = "adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=true\nrequired_family_count=3\n"
        result = self.run_exporter(delayed, ready_after=3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ATTEMPTS=3", result.stdout)
        result = self.run_exporter(delayed, ready_after=999)
        self.assertNotEqual(result.returncode, 0)
        self.assertLessEqual(int(result.stdout.split("ATTEMPTS=")[-1].split()[0]), 29)

    def test_exporter_capture_failures_and_stale_output_fail_closed(self):
        for mode in ("mktemp", "chmod", "read", "remove", "stale"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                script = self.exporter + textwrap.dedent(
                    f"""
                    set +e
                    run_dir={root}; capture={root}/capture; attempts={root}/attempts; printf 0 >"$attempts"; export MODE={mode} CAPTURE="$capture"
                    ssh_command=(fixture_ssh)
                    timeout_duration() {{ printf 1s; }}
                    deadline_sleep() {{ return 0; }}
                    mktemp() {{ [ "$MODE" = mktemp ] && return 1; : >"$CAPTURE"; printf %s "$CAPTURE"; }}
                    chmod() {{ [ "$MODE" = chmod ] && return 1; command chmod "$@"; }}
                    rm() {{ [ "$MODE" = remove ] && return 1; command rm "$@"; }}
                    timeout() {{
                      shift; n=$(<"$attempts"); n=$((n+1)); printf %s "$n" >"$attempts"
                      if [ "$MODE" = read ];then command rm -f "$CAPTURE"; printf '%s' canonical-on-unlinked-fd; return 0;fi
                      if [ "$MODE" = stale ]&&[ "$n" -eq 1 ];then fixture_ssh; return 1;fi
                      [ "$MODE" = stale ] && return 0
                      "$@"
                    }}
                    fixture_ssh() {{ printf 'adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=true\nrequired_family_count=3\n'; }}
                    exporter_metrics_ready $(($(date +%s%3N)+100)); rc=$?
                    printf 'RC=%s ATTEMPTS=%s\n' "$rc" "$(<"$attempts")"
                    [ "$rc" -ne 0 ] && [ "$(<"$attempts")" -le 29 ]
                    """
                )
                result = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("RC=1", result.stdout)

    def run_exporter(self, output, ready_after, mode="normal"):
        with tempfile.TemporaryDirectory() as directory:
            counter = pathlib.Path(directory) / "counter"
            script = self.exporter + textwrap.dedent(
                f"""
                run_dir={directory}; ssh_command=(fixture_ssh); printf 0 >{counter}; export EXPORT_MODE={mode}
                timeout_duration() {{ printf 2s; }}
                deadline_sleep() {{ return 0; }}
                timeout() {{ shift; if [ "$EXPORT_MODE" = timeout ];then n=$(<{counter}); echo $((n+1)) >{counter}; return 124;fi; "$@"; }}
                fixture_ssh() {{
                  [ "$*" = 'sudo -n discovery-stateful-adguard-inventory exporter-families' ] || return 88
                  n=$(<{counter}); n=$((n+1)); printf %s "$n" >{counter}
                  [ "$EXPORT_MODE" = nonzero ] && return 1
                  [ "$n" -ge {ready_after} ] || return 1
                  printf %b {output!r}
                }}
                if exporter_metrics_ready $(($(date +%s%3N)+30000));then rc=0;else rc=$?;fi
                printf 'ATTEMPTS=%s RC=%s\\n' "$(<{counter})" "$rc"
                exit "$rc"
                """
            )
            return subprocess.run(["bash", "-c", script], text=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
