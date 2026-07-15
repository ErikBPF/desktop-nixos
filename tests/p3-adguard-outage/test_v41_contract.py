import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


class ApprovedV41Contract(unittest.TestCase):
    def setUp(self):
        self.source = DRILL.read_text()

    def section(self, start, end):
        return self.source[self.source.index(start):self.source.index(end)]

    def test_manifest_binds_exact_executor_query_tuples(self):
        plan = self.section("plan=", "hash=")
        expected = (
            ("{nonce}.homelab.pastelariadev.com", "A", "fleet-a"),
            ("{nonce}.homelab.pastelariadev.com", "AAAA", "fleet-aaaa"),
            ("{nonce}.1-1-1-1.sslip.io", "A", "external"),
            ("{nonce}.2606-4700-4700--1111.sslip.io", "AAAA", "external"),
            ("{nonce}.invalid", "A", "nxdomain"),
            ("{nonce}.doubleclick.net", "A", "filtered"),
        )
        matrix = self.section("check_dns_matrix()", "worker_cleanup()")
        for template, rrtype, contract in expected:
            manifest_tuple = re.escape(
                f'{{contract:"{contract}",name_template:"{template}",type:"{rrtype}"}}'
            )
            self.assertRegex(plan, manifest_tuple)
            self.assertRegex(
                matrix,
                rf"(?m)^{re.escape(template)}\s+{rrtype}\s+\S+\s+{contract}$",
                f"executor must use manifest contract name {contract}",
            )

    def test_each_diagnostic_worker_emits_one_terminal_canonical_record(self):
        workers = self.section("worker_write_terminal()", "append_postrestore_matrix()")
        freeze = self.section("freeze_outage_evidence()", "recover()")
        for field in ("ordinal", "resolver_label", "transport", "rc_class", "status", "row_count"):
            self.assertIn(field, workers + freeze)
        self.assertRegex(workers + freeze, r"diagnostic-terminal|diagnostic_terminal")
        self.assertRegex(workers, r"diagnostic[^\n]*(?:wait|rc)[\s\S]*terminal")
        self.assertIn("best_effort_diagnostic=true", workers)
        self.assertRegex(workers, r'worker_pids=\(\);return "\$rc"')

    def test_diagnostic_terminal_records_cover_asymmetric_outcomes(self):
        body = self.section("worker_write_terminal()", "append_postrestore_matrix()")
        # A terminal record is required per PID, rather than one aggregate status
        # inferred from a combined row count; UDP may succeed while TCP times out.
        self.assertRegex(body, r"for pid in \"\$\{diagnostic_pids\[@\]\}\"")
        self.assertIn("diagnostic_terminal_files", body)
        self.assertRegex(body, r"rc_class[^\n]*(?:success|timeout|failed|cancelled)")
        self.assertRegex(body, r"row_count[^\n]*wc -l|wc -l[^\n]*row_count")

    def test_postrestore_artifact_is_explicit_state_machine(self):
        artifact = self.section("finish_artifact()", '[ "$authorization"')
        for field in ("postrestore_status", "postrestore_row_count", "postrestore_results_sha256"):
            self.assertIn(field, artifact)
        self.assertRegex(artifact, r"postrestore[^\n]*not-started")
        self.assertRegex(artifact, r"postrestore_results_sha256[^\n]*null")
        recovery = self.section("recover()", "postrestore_operational()")
        self.assertRegex(recovery, r"postrestore_status=(?:partial|failed)")
        self.assertRegex(recovery, r"postrestore_status=complete")
        complete = recovery.index("postrestore_status=complete")
        self.assertLess(recovery.index("postrestore_identity"), complete)
        self.assertLess(recovery.index("postrestore_operational"), complete)

    def test_fleet_a_parses_answer_rr_section_and_requires_exact_target(self):
        matrix = self.section("check_dns_matrix()", "worker_cleanup()")
        fleet = matrix[matrix.index("fleet-a)"):matrix.index("fleet-aaaa)")]
        self.assertRegex(fleet, r"ANSWER SECTION|answer_rr|answer_section")
        self.assertRegex(fleet, r"awk[^\n]*\$4==\"A\"")
        self.assertIn("192.168.10.210", fleet)
        self.assertRegex(fleet, r"sort -u|uniq")
        self.assertNotRegex(fleet, r"grep -q ['\"]192\\\.168\\\.10\\\.210")


if __name__ == "__main__":
    unittest.main()
