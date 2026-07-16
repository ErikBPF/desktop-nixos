import copy, hashlib, importlib.util, json, os, pathlib, stat, subprocess, sys, tempfile, unittest
from test_inventory import raw
ROOT=pathlib.Path(__file__).resolve().parents[2];COLLECTOR=ROOT/"modules/hosts/discovery/_stateful-adguard-inventory.py";PREFLIGHT=ROOT/"modules/hosts/discovery/_stateful-adguard-preflight.py";TRANSITION=ROOT/"modules/hosts/discovery/_stateful-adguard-transition.py";FIXTURE=ROOT/"modules/hosts/discovery/_stateful-adguard-transition-fixture.py"
def load(path,name):spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def normalized_baseline(value):
    api=value["api"]
    return {"api":{key:api[key] for key in ("enabled_filter_count","filter_count","filtering_enabled","protection_enabled","query_log_enabled","rewrite_count","user_rule_count")},"dns":{name:{"answered":probe["answer_count"]>0,"status":probe["status"]} for name,probe in value["dns"].items()},"exporter":{key:value["exporter"][key] for key in ("families","reachable","required_family_count")}}
def stable_containers(manifest):
    desired={item["name"]:item for item in manifest["resources"]["containers"]};images=manifest["resources"]["servarr"]["render_semantics"]["images"]
    result={}
    for name,new_id in (("adguard","8"*64),("adguard-exporter","9"*64)):
        item=desired[name];identity={key:item[key] for key in ("compose_labels","compose_project","compose_service","compose_working_dir","image_id","mounts","networks")};identity.update({"image_digest":images[name].rsplit("@",1)[1],"image_ref":images[name]});result[name]={"health":"healthy" if name=="adguard" else "none","id":new_id,"identity":identity,"restart_count":0,"state":"running"}
    return result
class Backend:
    def __init__(self,root,manifest,fail=None):self.root=pathlib.Path(root);self.root.mkdir(parents=True,exist_ok=True);self.manifest=manifest;self.fail=fail;self.calls=[];self.source=self.root/"source";self.restore=self.root/"restore";self.source.write_bytes(b"fixture-state\n");self.source.chmod(0o640);os.setxattr(self.source,b"user.p2",b"fixture")
    def run(self,phase,argv):
        self.calls.append((phase,argv))
        if phase==self.fail:raise RuntimeError("injected")
        if phase=="archive-work-volume":self.archive=self.source.read_bytes()
        if phase=="restore-work-non-live":self.restore.write_bytes(self.archive);self.restore.chmod(stat.S_IMODE(self.source.stat().st_mode));os.setxattr(self.restore,b"user.p2",os.getxattr(self.source,b"user.p2"))
        evidence={"argv_sha256":hashlib.sha256(json.dumps(argv,separators=(",",":" )).encode()).hexdigest()}
        if phase=="compare-non-live-restore":evidence.update({"acl_model":oct(stat.S_IMODE(self.restore.stat().st_mode)),"bytes_equal":self.source.read_bytes()==self.restore.read_bytes(),"gid":self.restore.stat().st_gid,"mode":f"{stat.S_IMODE(self.restore.stat().st_mode):04o}","uid":self.restore.stat().st_uid,"xattrs":sorted(os.listxattr(self.restore))})
        if phase=="scan-startup-fatal-logs":evidence={"containers":["adguard","adguard-exporter"],"fatal_matches":{"adguard":0,"adguard-exporter":0},"patterns_checked":len(argv[-1].split("|")),"raw_logs_retained":False,"status":"passed","version":1}
        if phase=="observe-stable-15-minutes":
            point={"baseline":normalized_baseline(self.manifest["resources"]["baseline"]),"containers":stable_containers(self.manifest)}
            evidence={"duration_seconds":900,"end":point,"raw_logs_retained":False,"sample_interval_seconds":30,"samples":31,"start":point,"status":"stable","version":1}
        return evidence
class EvidenceDriftBackend(Backend):
    def __init__(self,root,manifest,phase):super().__init__(root,manifest);self.drift_phase=phase
    def run(self,phase,argv):
        evidence=super().run(phase,argv)
        if phase==self.drift_phase=="scan-startup-fatal-logs":evidence["raw_logs_retained"]=True
        if phase==self.drift_phase=="observe-stable-15-minutes":evidence["end"]={**evidence["end"],"containers":{**evidence["end"]["containers"],"adguard":{**evidence["end"]["containers"]["adguard"],"restart_count":1}}}
        return evidence
class TransitionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.c=load(COLLECTOR,"tc");cls.p=load(PREFLIGHT,"tp");cls.t=load(TRANSITION,"tt");cls.f=load(FIXTURE,"tf")
    def setUp(self):
        self.p.TARGET_COMMIT="c"*40;self.inventory=self.c.normalize(raw());self.p.TARGET_IMAGE_REFS=self.inventory["servarr"]["render_semantics"]["images"]
        observation={"containers":[{"id":"1"*64,"name":"adguard"},{"id":"3"*64,"name":"adguard-exporter"}],"version":3}
        manifest={"actions":["verify-bindings"],"bindings":{"helper_sha256":"a"*64},"diagnostic_workers":[],"evidence_phases":["outage-core","postrestore"],"inventory_sha256":"","mode":"approved-outage-drill","network_contract_sha256":"b"*64,"probe_contracts":[],"probe_evidence":{},"required_workers":[],"resources":["adguard-exporter","adguard"],"shared_nonce":{},"version":4};manifest["inventory_sha256"]=self.t.digest(observation);manifest_envelope={"manifest":manifest,"manifest_sha256":self.t.digest(manifest)}
        result={"actual_elapsed_ms":1639,"core_evidence":{"rows":24,"status":"complete"},"core_partial_results_sha256":"c"*64,"core_results_sha256":"c"*64,"core_row_count":24,"diagnostic_evidence":{"rows":7,"status":"partial"},"diagnostic_results_sha256":None,"diagnostic_row_count":7,"diagnostic_status":"partial","failover_bound_ms":10000,"manifest_sha256":manifest_envelope["manifest_sha256"],"original_failure_rc":0,"outage_results_sha256":"c"*64,"partial_diagnostic_results_sha256":"d"*64,"partial_outage_results_sha256":"c"*64,"postrestore_evidence":{"rows":37,"status":"complete"},"postrestore_results_sha256":"e"*64,"postrestore_row_count":37,"postrestore_status":"complete","recovery_failed":False,"shared_nonce_sha256":"f"*64,"status":"passed","version":4}
        self.p3={"manifest_envelope":manifest_envelope,"observation":observation,"result":result}
        self.revisions={"forward":{"commit":"9969e35dca0cfb49a68bda3ba10156667cd4b53f","render_sha256":self.inventory["servarr"]["render_sha256"],"tree":"64d61bb25e0ee7cadda556e54ec86c4faf4f1fd8"},"prefetch":{"path":"/var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json","sha256":"6"*64},"rollback":{"commit":"b676063eafa53c00947c458d631493f98349f63c","render_sha256":"7"*64,"tree":"d312855e4a501995cb3f0216659d63763c6b3205"}}
    def approved(self):return self.t.envelope(self.t.plan(self.inventory,self.p3,self.t.LAYOUT,self.revisions,preflight=self.p))
    def test_inventory_binding_ignores_only_monotonic_stats(self):
        original=self.t.inventory_digest(self.inventory)
        for key in ("blocked_filtering","dns_queries"):
            changed=copy.deepcopy(self.inventory);changed["baseline"]["api"]["stats"][key]+=1
            self.assertEqual(self.t.inventory_digest(changed),original)
        changed=copy.deepcopy(self.inventory);changed["baseline"]["api"]["query_sample_count"]+=1
        self.assertNotEqual(self.t.inventory_digest(changed),original)
        manifest=self.approved()["manifest"]
        self.assertEqual(manifest["resources"]["baseline"]["api"]["stats"],self.inventory["baseline"]["api"]["stats"])
        self.assertEqual(manifest["version"],6)
    def test_exact_revision_channel_is_bound_before_recreate(self):
        manifest=self.approved()["manifest"];self.assertEqual(manifest["revision_contract"],self.revisions);self.assertIn("revision_helper_sha256",manifest["source_hashes"])
        forward=manifest["commands"][manifest["phases"].index("activate-forward-revision")];recreate_index=manifest["phases"].index("recreate-exact-pair");self.assertEqual(forward,["/run/wrappers/bin/sudo","-u","erik","--","servarr-exact-revision","activate","forward","--prefetch",self.revisions["prefetch"]["path"],"--authorization",self.t.LAYOUT["revision_forward_authorization"],"--output",self.t.BASE+"/forward-revision.json"]);self.assertLess(manifest["phases"].index("activate-forward-revision"),manifest["phases"].index("verify-compose-render"));self.assertLess(manifest["phases"].index("verify-compose-render"),recreate_index)
        self.assertEqual(manifest["recovery_commands"][0],["/run/wrappers/bin/sudo","-u","erik","--","servarr-exact-revision","activate","rollback","--prefetch",self.revisions["prefetch"]["path"],"--authorization",self.t.LAYOUT["revision_rollback_authorization"],"--output",self.t.BASE+"/rollback-revision.json"]);self.assertEqual(manifest["recovery_render_sha256"],self.revisions["rollback"]["render_sha256"])
        self.assertEqual(manifest["revision_authorizations"],{channel:self.t.REVISION.authorization(channel,self.revisions) for channel in ("forward","rollback")})
    def test_actual_p3_schema_cross_links_and_drift_fail_closed(self):
        approved=self.approved();self.assertFalse(approved["manifest"]["approval_ready"]);self.assertTrue(approved["manifest"]["source_hashes_valid"]);self.assertEqual(approved["manifest"]["blockers"],["declarative_executor_wiring_absent","revision_activation_helper_unwired","postcheck_helper_unwired"])
        for mutate in (lambda x:x["result"].update(status="failed"),lambda x:x["result"].update(core_row_count=23),lambda x:x["result"].update(recovery_failed=True),lambda x:x["result"].update(recovery_failed=0),lambda x:x["result"].pop("recovery_failed"),lambda x:x["result"]["postrestore_evidence"].update(status="partial"),lambda x:x["manifest_envelope"]["manifest"].update(resources=["adguard"]),lambda x:x["observation"].update(version=4)):
            changed=copy.deepcopy(self.p3);mutate(changed)
            with self.assertRaises(self.t.Drift):self.t.plan(self.inventory,changed,self.t.LAYOUT,self.revisions,preflight=self.p)
    def test_layout_sources_resources_and_production_argv_are_exact(self):
        approved=self.approved();self.assertEqual(approved,self.approved());manifest=approved["manifest"];self.assertEqual(set(manifest["evidence_layout"]),{"approved_authorization","approved_inventory","archive","archive_checksum","artifact_index","config_snapshot","journal","ledger","phase_ledger","restore_target","revision_forward_authorization","revision_forward_evidence","revision_rollback_authorization","revision_rollback_evidence","rollback_evidence"});self.assertEqual(manifest["phases"],self.t.PHASES);self.assertEqual(set(manifest["source_hashes"]),{"exact_revision_helper_sha256","fixture_executor_sha256","inventory_helper_sha256","planner_sha256","postcheck_helper_sha256","preflight_sha256","production_executor_sha256","revision_helper_sha256"})
        self.assertEqual(manifest["resources"]["containers"],self.inventory["containers"]);self.assertEqual(manifest["resources"]["servarr"],self.inventory["servarr"])
        self.assertEqual(manifest["commands"][2],["docker","stop","3"*64]);self.assertEqual(manifest["commands"][3],["docker","stop","1"*64]);self.assertEqual(manifest["commands"][4],["discovery-stateful-stack-ops","snapshot",self.t.LAYOUT["ledger"]])
        recreate=manifest["commands"][manifest["phases"].index("recreate-exact-pair")];self.assertEqual(recreate[:12],["docker-compose","--project-name","networking","--project-directory",self.t.WORKDIR,"--env-file",self.t.WORKDIR+"/.env","--env-file","/run/vault-agent/networking.env","-f",self.t.COMPOSE,"up"]);self.assertNotIn("fixture-",json.dumps(manifest["commands"]));self.assertNotIn("eval",json.dumps(manifest["commands"]))
        self.assertEqual(manifest["commands"][manifest["phases"].index("verify-recreated-identities")],["discovery-stateful-adguard-inventory","capture"])
        identity=manifest["phases"].index("verify-recreated-identities");logs=manifest["phases"].index("scan-startup-fatal-logs");stable=manifest["phases"].index("observe-stable-15-minutes");smoke=manifest["phases"].index("smoke-test");self.assertLess(identity,logs);self.assertLess(logs,stable);self.assertLess(stable,smoke)
        self.assertEqual(manifest["commands"][logs],[self.t.POSTCHECK_BIN,"startup-fatal-log-scan","--containers","adguard,adguard-exporter","--since","container-start","--output","counts-only","--fatal-patterns","|".join(self.t.FATAL_LOG_PATTERNS)])
        self.assertEqual(manifest["commands"][stable],[self.t.POSTCHECK_BIN,"stable-observation","--containers","adguard,adguard-exporter","--duration-seconds","900","--sample-interval-seconds","30","--baseline","full-normalized-start-end","--identity","exact-new-and-stable","--health","exact","--restarts","zero","--raw-logs","discard"])
    def test_disposable_two_boundary_fixture_preserves_source_and_metadata(self):
        approved=self.approved()
        with tempfile.TemporaryDirectory() as directory:
            backend=Backend(directory,approved["manifest"]);before=(backend.source.read_bytes(),backend.source.stat().st_uid,backend.source.stat().st_gid,stat.S_IMODE(backend.source.stat().st_mode),os.listxattr(backend.source));result=self.f.execute(approved,approved["manifest_sha256"],backend);after=(backend.source.read_bytes(),backend.source.stat().st_uid,backend.source.stat().st_gid,stat.S_IMODE(backend.source.stat().st_mode),os.listxattr(backend.source));self.assertEqual(before,after);self.assertEqual(result["status"],"completed");compare=next(row for row in result["ledger"] if row["phase"]=="compare-non-live-restore")["evidence"];self.assertTrue(compare["bytes_equal"]);self.assertIn("user.p2",compare["xattrs"]);self.assertEqual(compare["mode"],"0640")
            stable=next(row for row in result["ledger"] if row["phase"]=="observe-stable-15-minutes")["evidence"];self.assertEqual(stable["duration_seconds"],900);self.assertEqual(stable["start"],stable["end"]);self.assertFalse(stable["raw_logs_retained"])
            second=self.f.execute(approved,approved["manifest_sha256"],Backend(pathlib.Path(directory)/"second",approved["manifest"]),completed=result);self.assertTrue(second["idempotent"]);self.assertEqual(second["pending_actions"],[])
    def test_every_phase_failure_stops_and_no_shell_execution_surface(self):
        approved=self.approved()
        for index,phase in enumerate(self.t.PHASES):
            with self.subTest(phase=phase),tempfile.TemporaryDirectory() as directory:
                backend=Backend(directory,approved["manifest"],phase);result=self.f.execute(approved,approved["manifest_sha256"],backend);self.assertEqual(result["failed_phase"],phase);self.assertEqual([item for item,_ in backend.calls],self.t.PHASES[:index+1])
        for source in (TRANSITION.read_text(),FIXTURE.read_text()):
            for token in ("subprocess","shell=true","os.system","eval(","docker prune","volume prune","rm -rf","zfs destroy"):self.assertNotIn(token,source.lower())
    def test_post_recreate_semantic_failure_halts_inside_recovery_eligible_region(self):
        approved=self.approved();stop_index=approved["manifest"]["phases"].index("stop-adguard")
        for phase in ("scan-startup-fatal-logs","observe-stable-15-minutes"):
            with self.subTest(phase=phase),tempfile.TemporaryDirectory() as directory:
                result=self.f.execute(approved,approved["manifest_sha256"],EvidenceDriftBackend(directory,approved["manifest"],phase));self.assertEqual(result["status"],"failed");self.assertEqual(result["failed_phase"],phase);self.assertGreater(approved["manifest"]["phases"].index(phase),stop_index);self.assertNotIn("evidence",result["ledger"][-1])
    def test_declarative_wiring_marker_is_exact_and_cli_errors_are_value_free(self):
        prior=os.environ.get("P2_ADGUARD_DECLARATIVE_WIRING_SHA256")
        prior_binary=os.environ.get("P2_ADGUARD_EXACT_REVISION_BIN")
        prior_postcheck=os.environ.get("P2_ADGUARD_POSTCHECK_BIN");prior_postcheck_wiring=os.environ.get("P2_ADGUARD_POSTCHECK_WIRING_SHA256")
        try:
            os.environ["P2_ADGUARD_EXACT_REVISION_BIN"]="/nix/store/fixture/bin/servarr-exact-revision";os.environ["P2_ADGUARD_DECLARATIVE_WIRING_SHA256"]=self.t.source_hashes()["exact_revision_helper_sha256"];os.environ["P2_ADGUARD_POSTCHECK_BIN"]="/nix/store/fixture/bin/discovery-stateful-adguard-postcheck";os.environ["P2_ADGUARD_POSTCHECK_WIRING_SHA256"]=self.t.source_hashes()["postcheck_helper_sha256"];manifest=self.t.plan(self.inventory,self.p3,self.t.LAYOUT,self.revisions,preflight=self.p);self.assertTrue(manifest["approval_ready"]);self.assertEqual(manifest["blockers"],[]);self.assertEqual(manifest["commands"][manifest["phases"].index("scan-startup-fatal-logs")][0],os.environ["P2_ADGUARD_POSTCHECK_BIN"])
            os.environ["P2_ADGUARD_POSTCHECK_WIRING_SHA256"]="0"*64;drift=self.t.plan(self.inventory,self.p3,self.t.LAYOUT,self.revisions,preflight=self.p);self.assertFalse(drift["approval_ready"]);self.assertEqual(drift["blockers"],["postcheck_helper_unwired"])
        finally:
            if prior is None:os.environ.pop("P2_ADGUARD_DECLARATIVE_WIRING_SHA256",None)
            else:os.environ["P2_ADGUARD_DECLARATIVE_WIRING_SHA256"]=prior
            if prior_binary is None:os.environ.pop("P2_ADGUARD_EXACT_REVISION_BIN",None)
            else:os.environ["P2_ADGUARD_EXACT_REVISION_BIN"]=prior_binary
            if prior_postcheck is None:os.environ.pop("P2_ADGUARD_POSTCHECK_BIN",None)
            else:os.environ["P2_ADGUARD_POSTCHECK_BIN"]=prior_postcheck
            if prior_postcheck_wiring is None:os.environ.pop("P2_ADGUARD_POSTCHECK_WIRING_SHA256",None)
            else:os.environ["P2_ADGUARD_POSTCHECK_WIRING_SHA256"]=prior_postcheck_wiring
        with tempfile.TemporaryDirectory() as directory:
            paths=[]
            for index,value in enumerate((self.inventory,self.p3["manifest_envelope"],self.p3["observation"],self.p3["result"],{"not":"prefetch"})):
                path=pathlib.Path(directory)/str(index);path.write_text(json.dumps(value));paths.append(str(path))
            result=subprocess.run([sys.executable,TRANSITION,"plan",*paths],text=True,capture_output=True);self.assertEqual(result.returncode,1);self.assertEqual(result.stdout,"");self.assertRegex(result.stderr,r"^stateful-adguard-transition: BLOCKED: [A-Za-z]+\n$");self.assertNotIn(directory,result.stderr)
    def test_isolated_cli_uses_only_explicit_source_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            isolated=pathlib.Path(directory)/"planner.py";isolated.write_bytes(TRANSITION.read_bytes());helper=self.t.EXACT_REVISION;selected={channel:self.revisions[channel] for channel in ("forward","rollback")};contract={"fetch_ref":helper.FETCH_REF,"forward":selected["forward"],"remote":helper.REMOTE,"repository":str(helper.REPOSITORY),"rollback":selected["rollback"],"version":1};evidence={"fetched_origin_main":selected["forward"]["commit"],"forward":selected["forward"],"objects_present":True,"rollback":selected["rollback"],"version":1};prefetch={"contract":contract,"contract_sha256":helper._digest(contract),"evidence":evidence,"evidence_sha256":helper._digest(evidence)};paths=[]
            for index,value in enumerate((self.inventory,self.p3["manifest_envelope"],self.p3["observation"],self.p3["result"],prefetch)):
                path=pathlib.Path(directory)/str(index);path.write_text(json.dumps(value));paths.append(str(path))
            env=os.environ.copy();env.update({"P2_ADGUARD_INVENTORY_SOURCE":str(COLLECTOR),"P2_ADGUARD_PREFLIGHT_SOURCE":str(PREFLIGHT),"P2_ADGUARD_FIXTURE_SOURCE":str(FIXTURE),"P2_ADGUARD_EXECUTOR_SOURCE":str(ROOT/"modules/hosts/discovery/_stateful-adguard-transition-exec.py"),"P2_ADGUARD_REVISION_SOURCE":str(ROOT/"modules/hosts/discovery/_stateful-adguard-transition-revision.py"),"P2_ADGUARD_EXACT_REVISION_SOURCE":str(ROOT/"modules/server/_servarr-exact-revision.py"),"P2_ADGUARD_POSTCHECK_SOURCE":str(ROOT/"modules/hosts/discovery/_stateful-adguard-postcheck.py"),"P2_ADGUARD_EXACT_REVISION_BIN":"/nix/store/fixture-servarr-exact-revision/bin/servarr-exact-revision","P2_ADGUARD_POSTCHECK_BIN":"/nix/store/fixture-postcheck/bin/discovery-stateful-adguard-postcheck","P2_ADGUARD_POSTCHECK_WIRING_SHA256":self.t.source_hashes()["postcheck_helper_sha256"],"P2_ADGUARD_REVISION_PREFETCH_PATH":paths[4],"P2_ADGUARD_TARGET_COMMIT":self.inventory["servarr"]["commit"],"P2_ADGUARD_IMAGE_ADGUARD":self.inventory["servarr"]["render_semantics"]["images"]["adguard"],"P2_ADGUARD_IMAGE_EXPORTER":self.inventory["servarr"]["render_semantics"]["images"]["adguard-exporter"]})
            result=subprocess.run([sys.executable,isolated,"plan",*paths],env=env,text=True,capture_output=True);self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stderr,"");self.assertEqual(json.loads(result.stdout)["manifest"]["revision_contract"]["forward"],selected["forward"])
if __name__=="__main__":unittest.main()
