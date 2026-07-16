import copy,hashlib,importlib.util,json,os,pathlib,stat,tempfile,unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE=ROOT/"modules/hosts/discovery/_p3-observation-recover.py"
def load():
    spec=importlib.util.spec_from_file_location("recover",SOURCE);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
class RecoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.r=load()
    def fixture(self,directory):
        root=pathlib.Path(directory);old={key:"a"*64 for key in self.r.PROBE_FIELDS};new={key:"b"*64 for key in self.r.PROBE_FIELDS};current={"containers":[],"probe_evidence":new,"version":3};recovered={**current,"probe_evidence":old}
        manifest={"actions":["verify-bindings"],"bindings":{},"diagnostic_workers":[],"evidence_phases":["outage-core","postrestore"],"inventory_sha256":self.r.digest(recovered),"mode":"approved-outage-drill","network_contract_sha256":"c"*64,"probe_contracts":[],"probe_evidence":old,"required_workers":[],"resources":["adguard-exporter","adguard"],"shared_nonce":{},"version":4};envelope={"manifest":manifest,"manifest_sha256":self.r.digest(manifest)}
        rows=[]
        resolvers=("system","system","192.168.10.230","192.168.10.230");transports=("udp","tcp","udp","tcp")
        shapes=(("A","fleet-a","NOERROR","positive","fleet-a"),("AAAA","fleet-aaaa","NOERROR","zero","nodata"),("A","external","NOERROR","positive","external-positive"),("AAAA","external","NOERROR","positive","external-positive"),("A","nxdomain","NXDOMAIN","zero","nxdomain"),("A","filtered","NXDOMAIN","zero","filtered-nxdomain"))
        for worker in range(1,5):
            worker_rows=[]
            for item,(qtype,contract,status,count,classification) in enumerate(shapes,1):worker_rows.append(f"{worker:02d}:{item:02d}:{resolvers[worker-1]}:{transports[worker-1]}:{qtype}:{contract}:observed_rc=0:observed_status={status}:answer_count_class={count}:answer_classification={classification}:qname_sha256={'d'*64}")
            rows.append(worker_rows)
        frozen="\n".join(sum(rows,[]))+"\n";core=hashlib.sha256(frozen.encode()).hexdigest()
        diagnostic_rows=[[row.replace(":system:udp:",":2804:40a8:2f7:e101::1:udp:") for row in rows[0][:4]],[row.replace(":system:tcp:",":2804:40a8:2f7:e101::1:tcp:") for row in rows[1][:3]]];terminals=[{"ordinal":1,"rc_class":"cancelled","resolver_label":"gateway-rdnss","row_count":4,"status":"cancelled","transport":"udp"},{"ordinal":2,"rc_class":"cancelled","resolver_label":"gateway-rdnss","row_count":3,"status":"cancelled","transport":"tcp"}]
        diagnostic_evidence="\n".join(sum(diagnostic_rows,[]))+"".join(self.r.canonical(value).decode()+"\n" for value in terminals);diagnostic=hashlib.sha256((diagnostic_evidence+"\n").encode()).hexdigest()
        result={"actual_elapsed_ms":1,"core_evidence":{"rows":24,"status":"complete"},"core_partial_results_sha256":core,"core_results_sha256":core,"core_row_count":24,"diagnostic_evidence":{"rows":7,"status":"partial"},"diagnostic_results_sha256":None,"diagnostic_row_count":7,"diagnostic_status":"partial","failover_bound_ms":10000,"manifest_sha256":envelope["manifest_sha256"],"original_failure_rc":0,"outage_results_sha256":core,"partial_diagnostic_results_sha256":diagnostic,"partial_outage_results_sha256":core,"postrestore_evidence":{"rows":1,"status":"complete"},"postrestore_results_sha256":"f"*64,"postrestore_row_count":1,"postrestore_status":"complete","recovery_failed":False,"shared_nonce_sha256":"1"*64,"status":"passed","version":4}
        pairs=self.r.PREFIX+[("recovery-attempt","1"),("recovery-outcome","restored"),("postrestore-checks","started"),("postrestore-checks","passed")]
        journal=[{"event":event,"manifest_sha256":envelope["manifest_sha256"],"status":status,"version":1} for event,status in pairs]
        values=(current,envelope,result,journal);paths=[]
        for index,value in enumerate(values):
            path=root/f"input-{index}.json";path.write_text("\n".join(json.dumps(row,sort_keys=True,separators=(",",":")) for row in value)+"\n" if index==3 else json.dumps(value));paths.append(path)
        core_paths=[]
        for index,worker_rows in enumerate(rows,1):path=root/f"core-worker-{index:02d}.rows";path.write_text("\n".join(worker_rows)+"\n");core_paths.append(path)
        diagnostic_paths=[];terminal_paths=[]
        for index,worker_rows in enumerate(diagnostic_rows,1):path=root/f"diagnostic-worker-{index:02d}.rows";path.write_text("\n".join(worker_rows)+"\n");diagnostic_paths.append(path)
        for index,terminal in enumerate(terminals,1):path=root/f"diagnostic-terminal-{index:02d}.json";path.write_bytes(self.r.canonical(terminal)+b"\n");terminal_paths.append(path)
        self.r.EXPECTED_CURRENT_OBSERVATION_SHA256=self.r.digest(current);self.r.EXPECTED_MANIFEST_SHA256=envelope["manifest_sha256"];self.r.EXPECTED_RECOVERED_INVENTORY_SHA256=manifest["inventory_sha256"];self.r.EXPECTED_DIAGNOSTIC_RESULTS_SHA256=diagnostic
        return values,paths,core_paths,diagnostic_paths,terminal_paths,root/"preserved.json",root/"recovered.json"
    def run_fixture(self,directory,mutate=None):
        values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory)
        if mutate:mutate(values,paths,cores)
        report=self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals);return report,paths,preserved,recovered
    def test_recovers_only_probe_evidence_and_writes_0400(self):
        with tempfile.TemporaryDirectory() as directory:
            report,paths,preserved,recovered=self.run_fixture(directory);self.assertEqual(report["status"],"recovered");self.assertEqual(report["diagnostic_status"],"partial");self.assertEqual(report["diagnostic_row_count"],7);self.assertIn("partial_diagnostic_results_sha256",report);self.assertNotIn("diagnostic_results_sha256",report);self.assertEqual(preserved.read_bytes(),paths[0].read_bytes());self.assertEqual(stat.S_IMODE(preserved.stat().st_mode),0o400);self.assertEqual(stat.S_IMODE(recovered.stat().st_mode),0o400);self.assertEqual(self.r.digest(json.loads(recovered.read_bytes())),report["recovered_inventory_sha256"])
    def test_deterministic_report(self):
        with tempfile.TemporaryDirectory() as a,tempfile.TemporaryDirectory() as b:self.assertEqual(self.run_fixture(a)[0],self.run_fixture(b)[0])
    def test_retry_accepts_identical_0400_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            first=self.run_fixture(directory)[0];second=self.run_fixture(directory)[0];self.assertEqual(first,second)
    def test_existing_different_output_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory);preserved.write_bytes(b"different");preserved.chmod(0o400)
            with self.assertRaisesRegex(self.r.Blocked,"output-exists"):self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals)
    def test_partial_publication_resumes(self):
        with tempfile.TemporaryDirectory() as directory:
            values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory);preserved.write_bytes(paths[0].read_bytes());preserved.chmod(0o400);self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals);self.assertTrue(recovered.is_file())
    def assert_blocked(self,mutate,reason):
        with tempfile.TemporaryDirectory() as directory:
            values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory);mutate(values,paths,cores)
            with self.assertRaisesRegex(self.r.Blocked,reason):self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals)
    def rewrite(self,values,paths,index):paths[index].write_text("\n".join(json.dumps(row) for row in values[index])+"\n" if index==3 else json.dumps(values[index]))
    def test_manifest_hash_tamper(self):self.assert_blocked(lambda v,p,c:(v[1].update(manifest_sha256="0"*64),self.rewrite(v,p,1)),"manifest-identity")
    def test_inventory_binding_tamper(self):
        def mutate(v,p,c):v[1]["manifest"]["inventory_sha256"]="0"*64;v[1]["manifest_sha256"]=self.r.digest(v[1]["manifest"]);v[2]["manifest_sha256"]=v[1]["manifest_sha256"];self.rewrite(v,p,1);self.rewrite(v,p,2);[row.update(manifest_sha256=v[1]["manifest_sha256"]) for row in v[3]];self.rewrite(v,p,3)
        self.assert_blocked(mutate,"manifest-identity")
    def test_result_manifest_binding_tamper(self):self.assert_blocked(lambda v,p,c:(v[2].update(manifest_sha256="0"*64),self.rewrite(v,p,2)),"result-binding")
    def test_recovery_failed_tamper(self):self.assert_blocked(lambda v,p,c:(v[2].update(recovery_failed=True),self.rewrite(v,p,2)),"result-binding")
    def test_result_schema_tamper(self):self.assert_blocked(lambda v,p,c:(v[2].pop("recovery_failed"),self.rewrite(v,p,2)),"result-schema")
    def test_journal_binding_tamper(self):self.assert_blocked(lambda v,p,c:(v[3][0].update(manifest_sha256="0"*64),self.rewrite(v,p,3)),"journal-binding")
    def test_journal_contract_tamper(self):self.assert_blocked(lambda v,p,c:(v[3][-1].update(status="failed"),self.rewrite(v,p,3)),"journal-contract")
    def test_core_row_tamper(self):self.assert_blocked(lambda v,p,c:c[0].write_text(c[0].read_text().replace("observed_rc=0","observed_rc=1",1)),"core-rows")
    def test_core_hash_tamper(self):self.assert_blocked(lambda v,p,c:(v[2].update(core_results_sha256="0"*64),self.rewrite(v,p,2)),"core-binding")
    def test_pinned_identities_are_exact(self):
        source=SOURCE.read_text();self.assertIn("d5cf3b5979d88ece2582df3010d28e5f89fc7e440dc31c4838f6b1f28ee3cc40",source);self.assertIn("6977c47a3779bdd1086473065bb106b6b9a4ff54bf8c540a9924632446cf6601",source);self.assertIn("be6a935c0e228fdffb1ac90185df767eb21ab23c0401b4b36b2c689ce14def59",source);self.assertIn("aebce43d85fc62812445e079e471066014aff901cdd4dbebb00c1bcfd83c5629",source)
    def test_diagnostic_hash_tamper(self):self.assert_blocked(lambda v,p,c:(v[2].update(partial_diagnostic_results_sha256="0"*64),self.rewrite(v,p,2)),"diagnostic-binding")
    def test_diagnostic_row_tamper(self):
        with tempfile.TemporaryDirectory() as directory:
            values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory);diagnostics[0].write_text(diagnostics[0].read_text().replace("observed_rc=0","observed_rc=1",1))
            with self.assertRaisesRegex(self.r.Blocked,"diagnostic-rows"):self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals)
    def test_diagnostic_terminal_tamper(self):
        with tempfile.TemporaryDirectory() as directory:
            values,paths,cores,diagnostics,terminals,preserved,recovered=self.fixture(directory);terminal=json.loads(terminals[0].read_bytes());terminal["row_count"]=3;terminals[0].write_text(json.dumps(terminal))
            with self.assertRaisesRegex(self.r.Blocked,"diagnostic-terminal"):self.r.recover(*paths,preserved,recovered,cores,diagnostics,terminals)
    def test_current_observation_identity_tamper(self):self.assert_blocked(lambda v,p,c:(v[0].update(extra="field"),self.rewrite(v,p,0)),"current-observation-identity")
    def test_fourth_recovery_attempt_blocks(self):
        def mutate(v,p,c):v[3].insert(-3,{"event":"recovery-attempt","manifest_sha256":v[1]["manifest_sha256"],"status":"4","version":1});self.rewrite(v,p,3)
        self.assert_blocked(mutate,"journal-contract")
if __name__=="__main__":unittest.main()
