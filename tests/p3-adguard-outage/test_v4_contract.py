import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


class ApprovedV4Contract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()

    def section(self, start, end):
        return self.source[self.source.index(start):self.source.index(end)]

    def test_manifest_v4_binds_workers_contracts_and_actions(self):
        plan = self.section("plan=", "hash=")
        for token in ("version:4", "required_workers", "diagnostic_workers", "probe_contracts", "actions"):
            self.assertIn(token, plan)
        expected = (
            ('fleet-a', '{nonce}.homelab.pastelariadev.com', 'A'),
            ('fleet-aaaa', '{nonce}.homelab.pastelariadev.com', 'AAAA'),
            ('external', '{nonce}.1-1-1-1.sslip.io', 'A'),
            ('external', '{nonce}.2606-4700-4700--1111.sslip.io', 'AAAA'),
            ('nxdomain', '{nonce}.invalid', 'A'),
            ('filtered', '{nonce}.doubleclick.net', 'A'),
        )
        for contract, template, rrtype in expected:
            self.assertIn(
                f'{{contract:"{contract}",name_template:"{template}",type:"{rrtype}"}}',
                plan,
            )
        for resolver in ("system", "gateway", "kepler"):
            self.assertIn(resolver, plan)
        for transport in ("udp", "tcp"):
            self.assertIn(transport, plan)

    def test_core_is_four_workers_twenty_four_rows_under_ten_seconds(self):
        workers = self.section("run_outage_workers()", "append_postrestore_matrix()")
        self.assertRegex(workers, r"core[^\n]*resolvers=\(system system 192\.168\.10\.230 192\.168\.10\.230\)")
        self.assertRegex(workers, r"core[^\n]*transports=\(udp tcp udp tcp\)")
        self.assertRegex(workers, r"for .* in 01 02 03 04")
        self.assertRegex(self.source, r"(?:wc -l|row_count)[^\n]*24|24[^\n]*(?:wc -l|row_count)")
        self.assertRegex(self.source, r"\.failover_bound_ms>0 and \.failover_bound_ms<=10000")

    def test_one_shared_fresh_nonce_is_generated_after_stopped_gate(self):
        stopped = self.source.index("record stopped-gate passed")
        generators = [m.start() for m in re.finditer(r"(?:od .*?/dev/urandom|generate_nonce)", self.source) if m.start() > stopped]
        self.assertEqual(len(generators), 1)
        self.assertGreater(generators[0], stopped)
        worker = self.section("check_dns_matrix()", "worker_cleanup()")
        self.assertNotRegex(worker, r"od .*?/dev/urandom")
        self.assertIn("nonce=$5", worker)
        self.assertIn("outage_nonce_sha256", self.source[stopped:])

    def test_gateway_diagnostic_is_concurrent_best_effort_zero_to_twelve_rows(self):
        workers = self.section("run_outage_workers()", "append_postrestore_matrix()")
        self.assertRegex(workers, r"diagnostic[^\n]*resolvers=\(\"?\$rdnss\"? \"?\$rdnss\"?\)")
        self.assertRegex(workers, r"diagnostic[^\n]*transports=\(udp tcp\)")
        self.assertRegex(workers, r"diagnostic[^\n]*(?:best_effort|best-effort)|(?:best_effort|best-effort)[^\n]*diagnostic")
        self.assertRegex(self.source, r"diagnostic_row_count|0\.\.12")
        self.assertIn('for pid in "${diagnostic_pids[@]}";do wait "$pid" 2>/dev/null||true;done', workers)

    def test_core_failure_blocks_while_diagnostic_failure_does_not(self):
        workers = self.section("run_outage_workers()", "append_postrestore_matrix()")
        self.assertRegex(workers, r"core[^\n]*(?:failed|rc|status)")
        self.assertRegex(workers, r"core[^\n]*(?:return 1|rc=1)|(?:return 1|rc=1)[^\n]*core")
        self.assertIn("best_effort_diagnostic=true", workers)
        self.assertNotRegex(workers, r"wait \"\$pid\"[^\n]*diagnostic[^\n]*rc=1")

    def test_public_answers_cannot_fake_fleet_or_filter_contracts(self):
        matrix = self.section("check_dns_matrix()", "worker_cleanup()")
        self.assertIn("192.168.10.210", matrix[matrix.index("fleet-a)"):matrix.index("fleet-aaaa)")])
        self.assertRegex(matrix, r"filtered\)[\s\S]*(?:NXDOMAIN|0\\\.0\\\.0\\\.0)")
        self.assertRegex(matrix, r"external-(?:a|aaaa)\)|external\)")
        self.assertIn("case $contract in", matrix)

    def test_artifact_has_separate_deterministic_phase_hashes_and_counts(self):
        artifact = self.section("finish_artifact()", "[ \"$authorization\"")
        for field in ("core_results_sha256", "core_row_count", "diagnostic_results_sha256",
                      "diagnostic_row_count", "diagnostic_status", "postrestore_results_sha256",
                      "postrestore_row_count", "postrestore_status"):
            self.assertIn(field, artifact)
        self.assertIn("postrestore_evidence:{rows:$postrestore_rows,status:$postrestore_status}", artifact)
        self.assertIn('if $postrestore_results_sha256=="" then null', artifact)
        self.assertRegex(self.source, r"LC_ALL=C sort|sort -s")
        self.assertIn('--arg outage_results_sha256 "${frozen_outage_results_sha256:-}"', artifact)
        self.assertIn('--arg diagnostic_results_sha256 "${frozen_diagnostic_results_sha256:-}"', artifact)
        self.assertIn('--arg postrestore_results_sha256 "$postrestore_results_sha"', artifact)

    def test_postrestore_gateway_adguard_kepler_are_all_mandatory(self):
        post = self.section("restored_operational_checks()", "exporter_metrics_ready()")
        for resolver in ("$rdnss", "192.168.10.210", "192.168.10.230"):
            self.assertIn(resolver, post)
        for transport in ("udp", "tcp"):
            self.assertIn(transport, post)
        self.assertNotRegex(post, r"(?:\$rdnss|gateway)[^\n]*(?:\|\| true|best.?effort)")
        self.assertRegex(post, r"(?:\$rdnss|gateway)[^\n]*(?:return 1|\|\| return 1)")

    def test_deadline_and_cancel_cover_core_and_diagnostic(self):
        workers = self.section("run_outage_workers()", "append_postrestore_matrix()")
        self.assertRegex(workers, r"core_pids|worker_pids[^\n]*core")
        self.assertRegex(workers, r"diagnostic_pids|worker_pids[^\n]*diagnostic")
        self.assertRegex(workers, r"cancel[^\n]*(?:core|worker)")
        self.assertRegex(workers, r"diagnostic_pids[^\n]*kill|kill[^\n]*diagnostic_pids")
        self.assertIn("outage_deadline", workers)
        self.assertIn("wait", workers)

    def test_v4_rejects_version_inventory_binding_and_authorization_drift(self):
        self.assertRegex(self.source, r"\.version==3")
        self.assertIn("version:4", self.section("plan=", "hash="))
        for token in ("network_contract_sha", "inventory_sha", "binding-drift", "inventory-drift"):
            self.assertIn(token, self.source)
        self.assertRegex(self.source, r"\[ \"\$authorization\" = \"\$hash\" \]")

    def test_canonical_hash_fixture_keeps_phases_separate(self):
        command = r'''set -euo pipefail
hash_rows(){ printf '%s\n' "$@"|LC_ALL=C sort -s -t: -k1,1n -k2,2n|sha256sum|cut -d' ' -f1; }
a=$(hash_rows '04:01:core-d' '01:01:core-a' '03:01:core-c' '02:01:core-b')
b=$(hash_rows '02:01:core-b' '03:01:core-c' '01:01:core-a' '04:01:core-d')
[ "$a" = "$b" ]
d=$(hash_rows '06:01:diagnostic-b' '05:01:diagnostic-a')
p=$(hash_rows '00:01:postrestore')
[ "$a" != "$d" ] && [ "$a" != "$p" ] && [ "$d" != "$p" ]'''
        result = subprocess.run(["bash", "-c", command], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
