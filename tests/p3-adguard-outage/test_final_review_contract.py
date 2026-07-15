import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"
OBSERVE = ROOT / "scripts/p3-adguard-outage-observe.sh"


class FinalReviewContract(unittest.TestCase):
    def test_filtering_accepts_block_address_or_nxdomain(self):
        for path in (OBSERVE, DRILL):
            source = path.read_text()
            filtered = re.search(
                r"filtered\).*?(?=;;)", source, flags=re.DOTALL
            )
            self.assertIsNotNone(filtered, path.name)
            contract = filtered.group(0)
            self.assertIn("0\\.0\\.0\\.0", contract, path.name)

            # Filtering is the one probe whose valid status depends on how the
            # resolver represents a blocked name. It must not be rejected by a
            # preceding unconditional NOERROR assertion.
            function_name = "probe_matrix" if path == OBSERVE else "check_dns_matrix"
            probe_body = source[source.index(function_name) :]
            self.assertNotIn('grep -q "status: $status"', probe_body, path.name)
            self.assertIn('[ "$dns_status" = NXDOMAIN ]', contract, path.name)
            self.assertIn('[ "$dns_status" = NOERROR ]', contract, path.name)

    def test_outage_uses_one_deadline_for_complete_three_path_matrix(self):
        source = DRILL.read_text()
        second_stop = source.index('"docker stop $adguard_id"')
        outage = source[second_stop:]

        timer = outage.index("date +%s%3N")
        stopped_gate = outage.index("record stopped-gate started")
        self.assertLess(timer, stopped_gate)
        self.assertNotIn("matrix_start=", outage)

        proof_end = outage.index("record secondary-matrix passed")
        proof = outage[:proof_end]
        self.assertRegex(proof, r"check_dns_matrix\s+system\s+\"\$transport\"")
        self.assertRegex(proof, r"check_dns_matrix\s+\"\$rdnss\"\s+\"\$transport\"")
        self.assertRegex(proof, r"check_dns_matrix\s+192\.168\.10\.230\s+\"\$transport\"")
        self.assertIn("for transport in udp tcp", proof)

    def test_postrestore_checks_run_after_restore_even_when_outage_proof_failed(self):
        source = DRILL.read_text()
        recover = source[source.index("recover() {") : source.index("trap recover EXIT")]
        self.assertNotIn('$ok && [ "$original" -eq 0 ]', recover)
        identity = recover.index("postrestore_identity")
        operational = recover.index("postrestore_operational")
        self.assertGreater(operational, identity)

    def test_ssh_cannot_fall_back_to_global_known_hosts(self):
        for path in (OBSERVE, DRILL):
            source = path.read_text()
            self.assertIn("GlobalKnownHostsFile=/dev/null", source, path.name)
            self.assertIn("StrictHostKeyChecking=yes", source, path.name)
            self.assertIn("UserKnownHostsFile=", source, path.name)

    def test_probe_evidence_binds_normalized_result_and_qname_hash(self):
        source = OBSERVE.read_text()
        for field in ("qname_sha256", "observed_rc", "answer_count_class",
                      "observed_status", "answer_classification"):
            self.assertIn(field, source)
        self.assertNotIn(':pass\\n"', source)

    def test_every_public_probe_qname_is_nonce_derived(self):
        for path in (OBSERVE, DRILL):
            source = path.read_text()
            self.assertNotIn("example.com A", source, path.name)
            self.assertNotIn("example.com AAAA", source, path.name)
            self.assertIn("{nonce}.1-1-1-1.sslip.io A", source, path.name)
            self.assertIn("{nonce}.2606-4700-4700--1111.sslip.io AAAA", source, path.name)


if __name__ == "__main__":
    unittest.main()
