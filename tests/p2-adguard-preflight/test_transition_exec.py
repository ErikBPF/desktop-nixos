import copy, hashlib, importlib, importlib.util, json, pathlib, subprocess, sys, tempfile, unittest
from unittest import mock
ROOT=pathlib.Path(__file__).resolve().parents[2];EXEC=ROOT/"modules/hosts/discovery/_stateful-adguard-transition-exec.py";POSTCHECK=ROOT/"modules/hosts/discovery/_stateful-adguard-postcheck.py"
def load():spec=importlib.util.spec_from_file_location("transition_exec",EXEC);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def load_postcheck():spec=importlib.util.spec_from_file_location("transition_postcheck",POSTCHECK);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
POSTCHECK_MODULE=load_postcheck()
def self_digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()).hexdigest()
class Runner:
    def __init__(self,inventory,layout,fail=None,recovery_fail=False,post_mutation=None,rollback=None,revision_mutation=None,revision_missing=False,verify_inventory=None):self.inventory=copy.deepcopy(inventory);self.layout=layout;self.fail=fail;self.recovery_fail=recovery_fail;self.post_mutation=post_mutation;self.rollback=rollback;self.revision_mutation=revision_mutation;self.revision_missing=revision_missing;self.verify_inventory=copy.deepcopy(verify_inventory);self.calls=[];self.captures=0
    def capture_inventory(self):self.captures+=1;return copy.deepcopy(self.inventory)
    def snapshot_binding(self,path):
        return {"path":str(pathlib.Path(path)),"uuid":"11111111-1111-1111-1111-111111111111"}
    def run(self,phase,argv):
        self.calls.append((phase,argv))
        if phase.startswith("stop-"):
            for key in ("approved_inventory","approved_authorization","revision_forward_authorization","revision_rollback_authorization","phase_ledger","journal"):assert pathlib.Path(self.layout[key]).exists()
        if phase==self.fail:raise RuntimeError("injected")
        if phase.startswith("recovery-") and (self.recovery_fail is True or self.recovery_fail==phase):raise RuntimeError("recovery injected")
        if phase=="verify-bindings":return {"inventory":copy.deepcopy(self.verify_inventory if self.verify_inventory is not None else self.inventory)}
        if phase=="scan-startup-fatal-logs":return {"containers":["adguard","adguard-exporter"],"fatal_matches":{"adguard":0,"adguard-exporter":0},"patterns_checked":4,"raw_logs_retained":False,"status":"passed","version":1}
        if phase=="observe-stable-15-minutes":
            start=POSTCHECK_MODULE._normalized_point(self._post_inventory());return {"duration_seconds":900,"end":copy.deepcopy(start),"raw_logs_retained":False,"sample_interval_seconds":30,"samples":31,"start":start,"status":"stable","version":1}
        if phase in ("activate-forward-revision","recovery-activate-rollback"):
            channel="forward" if phase=="activate-forward-revision" else "rollback";prefetch=json.loads(pathlib.Path(argv[8]).read_text());authorization=json.loads(pathlib.Path(argv[10]).read_text());selected=authorization["authorization"]["selected"];evidence={"authorization_sha256":authorization["authorization_sha256"],"encrypted_blob_changed":False,"head":selected["commit"],"idempotent":False,"prefetch_sha256":prefetch["evidence_sha256"],"selection":channel,"status":"activated","tree":selected["tree"],"version":1}
            if self.revision_mutation:self.revision_mutation(evidence)
            envelope={"evidence":evidence,"evidence_sha256":self_digest(evidence)}
            if not self.revision_missing:pathlib.Path(argv[-1]).write_text(json.dumps(envelope,sort_keys=True,separators=(",",":")))
        if phase=="write-ledger":self.rollback_command=argv[-2];pathlib.Path(self.layout["ledger"]).write_text("fixture ledger")
        if phase=="snapshot-config-readonly":pathlib.Path(self.layout["config_snapshot"]).mkdir()
        if phase=="archive-work-volume":pathlib.Path(self.layout["archive"]).write_bytes(b"archive");pathlib.Path(self.layout["archive_checksum"]).write_text("checksum")
        if phase=="restore-work-non-live":pathlib.Path(self.layout["restore_target"]).mkdir(mode=0o700)
        if phase in ("verify-recreated-identities","smoke-test","recovery-verify-identities"):
            post=copy.deepcopy(self.inventory)
            for index,item in enumerate(post["containers"]):item["id"]=("8" if index==0 else "9")*64
            adguard=next(item for item in post["containers"] if item["name"]=="adguard");post["volume"]["references"]=[adguard["id"]]
            if phase=="recovery-verify-identities":post["servarr"].update(commit="b676063eafa53c00947c458d631493f98349f63c",render_sha256="7"*64)
            else:
                post["servarr"].update(commit="9969e35dca0cfb49a68bda3ba10156667cd4b53f")
                for item in post["containers"]:item["image_ref"]=post["servarr"]["render_semantics"]["images"][item["name"]]
            if self.post_mutation:self.post_mutation(post)
            return {"inventory":post}
        if phase=="record-rollback-evidence":
            adguard=next(item for item in self.inventory["containers"] if item["name"]=="adguard");import hashlib
            evidence=self.rollback or {"archive":self.layout["archive"],"container":adguard["id"],"image_sha256":hashlib.sha256((adguard["image_ref"]+"@"+adguard["image_digest"]).encode()).hexdigest(),"rollback_command_sha256":hashlib.sha256(self.rollback_command.encode()).hexdigest(),"rollback_not_executed":True,"snapshot":self.layout["config_snapshot"]};pathlib.Path(self.layout["rollback_evidence"]).write_text(json.dumps(evidence,sort_keys=True,separators=(",",":")));pathlib.Path(self.layout["rollback_evidence"]).chmod(0o400);return evidence
        return {"stdout_sha256":("7"*64 if phase=="recovery-verify-rollback-render" else self.render_sha) if phase in ("verify-compose-render","recovery-verify-rollback-render") else "0"*64}
    def _post_inventory(self):
        post=copy.deepcopy(self.inventory)
        for index,item in enumerate(post["containers"]):item["id"]=("8" if index==0 else "9")*64
        adguard=next(item for item in post["containers"] if item["name"]=="adguard");post["volume"]["references"]=[adguard["id"]];post["servarr"].update(commit="9969e35dca0cfb49a68bda3ba10156667cd4b53f")
        for item in post["containers"]:item["image_ref"]=post["servarr"]["render_semantics"]["images"][item["name"]]
        return post
class TransitionExecTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.e=load()
    def setUp(self):
        transition_tests=importlib.import_module("test_transition");transition_tests.TransitionTest.setUpClass();case=transition_tests.TransitionTest(methodName="test_actual_p3_schema_cross_links_and_drift_fail_closed");case.setUp();self.case=case;self.base=case.approved()
    def contract(self,root):
        value=copy.deepcopy(self.base);layout={key:str(pathlib.Path(root)/key) for key in value["manifest"]["evidence_layout"]};value["manifest"]["evidence_layout"]=layout
        helper_path=ROOT/"modules/server/_servarr-exact-revision.py";spec=importlib.util.spec_from_file_location("exact_revision_contract",helper_path);helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
        selected={channel:copy.deepcopy(value["manifest"]["revision_contract"][channel]) for channel in ("forward","rollback")};contract={"fetch_ref":helper.FETCH_REF,"forward":selected["forward"],"remote":helper.REMOTE,"repository":str(helper.REPOSITORY),"rollback":selected["rollback"],"version":1};evidence={"fetched_origin_main":selected["forward"]["commit"],"forward":selected["forward"],"objects_present":True,"rollback":selected["rollback"],"version":1};envelope={"contract":contract,"contract_sha256":helper._digest(contract),"evidence":evidence,"evidence_sha256":helper._digest(evidence)};helper.validate_prefetch(envelope)
        prefetch=pathlib.Path(root)/"revision-prefetch.json";prefetch.write_bytes(helper._canonical(envelope)+b"\n");value["manifest"]["revision_contract"]["prefetch"]={"path":str(prefetch),"sha256":__import__("hashlib").sha256(prefetch.read_bytes()).hexdigest()}
        value["manifest"]["revision_authorizations"]={channel:self.case.t.REVISION.authorization(channel,value["manifest"]["revision_contract"]) for channel in ("forward","rollback")}
        value["manifest"]["commands"][9][8]=str(prefetch);value["manifest"]["commands"][9][10]=layout["revision_forward_authorization"];value["manifest"]["commands"][9][-1]=layout["revision_forward_evidence"];value["manifest"]["recovery_commands"][0][8]=str(prefetch);value["manifest"]["recovery_commands"][0][10]=layout["revision_rollback_authorization"];value["manifest"]["recovery_commands"][0][-1]=layout["revision_rollback_evidence"]
        for channel in ("forward","rollback"):helper._validate_authorization(value["manifest"]["revision_authorizations"][channel],envelope,channel,prefetch)
        value["manifest_sha256"]=self.case.t.digest(value["manifest"]);return value,layout
    def test_drift_or_existing_evidence_blocks_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout);runner.inventory["containers"][0]["restart_count"]=1
            with self.assertRaises(self.e.Drift):self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True)
            self.assertEqual(runner.calls,[])
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);changed=copy.deepcopy(self.case.inventory);changed["containers"][0]["restart_count"]=1;runner=Runner(self.case.inventory,layout,verify_inventory=changed)
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True)
            self.assertEqual(result["failed_phase"],"verify-bindings");self.assertEqual([phase for phase,_ in runner.calls],["verify-bindings"]);self.assertFalse(any(phase.startswith("stop-") for phase,_ in runner.calls));self.assertFalse(pathlib.Path(layout["ledger"]).exists())
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);contract["manifest"]["revision_authorizations"]["rollback"]["authorization"]["selection"]="forward";contract["manifest_sha256"]=self.case.t.digest(contract["manifest"]);runner=Runner(self.case.inventory,layout)
            with self.assertRaises(self.e.Drift):self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True)
            self.assertEqual(runner.calls,[])
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);pathlib.Path(layout["archive"]).write_text("existing");runner=Runner(self.case.inventory,layout)
            with self.assertRaises(self.e.Drift):self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True)
            self.assertEqual(runner.calls,[])
    def test_failure_after_stop_runs_only_exact_pair_recovery_and_retains_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,fail="archive-work-volume");runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["failed_phase"],"archive-work-volume")
            self.assertEqual(runner.calls[-4],("recovery-activate-rollback",contract["manifest"]["recovery_commands"][0]));self.assertEqual(runner.calls[-3][0],"recovery-verify-rollback-render");self.assertEqual(runner.calls[-2],("recovery-recreate-exact-pair",contract["manifest"]["recovery_commands"][2]));self.assertEqual(runner.calls[-1][0],"recovery-verify-identities");self.assertTrue(pathlib.Path(layout["journal"]).exists());self.assertTrue(pathlib.Path(layout["approved_inventory"]).exists());self.assertNotIn("restore-work-non-live",[phase for phase,_ in runner.calls])
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,fail="stop-adguard-exporter");runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertFalse(result["recovery_failed"]);self.assertIn("recovery-activate-rollback",[phase for phase,_ in runner.calls])
    def test_production_runner_parses_normalized_inventory_after_recreate(self):
        inventory=copy.deepcopy(self.case.inventory);inventory["containers"][0]["id"]="8"*64;inventory["containers"][1]["id"]="9"*64
        completed=mock.Mock(stdout=json.dumps(inventory).encode())
        with mock.patch.object(self.e.subprocess,"run",return_value=completed) as run:
            evidence=self.e.ProductionRunner(self.case.t.LAYOUT).run("verify-recreated-identities",["discovery-stateful-adguard-inventory","capture"])
        self.assertEqual(evidence["inventory"]["containers"][0]["id"],"8"*64);run.assert_called_once()
        post=POSTCHECK_MODULE._normalized_point(Runner(self.case.inventory,self.case.t.LAYOUT)._post_inventory());raw={"duration_seconds":900,"end":post,"raw_logs_retained":False,"sample_interval_seconds":30,"samples":31,"start":post,"status":"stable","version":1};completed=mock.Mock(stdout=json.dumps(raw).encode())
        with mock.patch.object(self.e.subprocess,"run",return_value=completed) as run:
            self.assertEqual(self.e.ProductionRunner(self.case.t.LAYOUT).run("observe-stable-15-minutes",["postcheck"]),raw);run.assert_called_once();self.assertEqual(run.call_args.kwargs["timeout"],950)
    def test_production_runner_captures_inventory_without_nested_sudo(self):
        completed=mock.Mock(stdout=json.dumps(self.case.inventory))
        with mock.patch.object(self.e.subprocess,"run",return_value=completed) as run:
            self.assertEqual(self.e.ProductionRunner(self.case.t.LAYOUT).capture_inventory(),self.case.inventory)
        self.assertEqual(run.call_args.args[0],["sudo","-n","/run/current-system/sw/bin/discovery-stateful-adguard-inventory","capture"])
    def test_complete_then_identical_second_run_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout);runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["status"],"completed");self.assertEqual([row["phase"] for row in result["ledger"]],contract["manifest"]["phases"]);self.assertEqual(pathlib.Path(layout["revision_forward_authorization"]).stat().st_mode & 0o777,0o444);self.assertEqual(pathlib.Path(layout["revision_rollback_authorization"]).stat().st_mode & 0o777,0o444)
            second=self.e.execute(contract,contract["manifest_sha256"],Runner(self.case.inventory,layout),allow_unwired=True,allow_fixture_layout=True);self.assertTrue(second["idempotent"]);self.assertEqual(second["pending_actions"],[])
            pathlib.Path(layout["archive"]).write_bytes(b"drift")
            with self.assertRaises(self.e.Drift):self.e.execute(contract,contract["manifest_sha256"],Runner(self.case.inventory,layout),allow_unwired=True,allow_fixture_layout=True)
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,revision_mutation=lambda evidence:evidence.update(head="0"*40));runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["failed_phase"],"activate-forward-revision")
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,revision_missing=True);runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["failed_phase"],"activate-forward-revision")
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout);runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"];self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);pathlib.Path(layout["revision_rollback_evidence"]).write_text("unexpected")
            with self.assertRaises(self.e.Drift):self.e.execute(contract,contract["manifest_sha256"],Runner(self.case.inventory,layout),allow_unwired=True,allow_fixture_layout=True)
    def test_post_recreate_binds_new_ids_and_rejects_identity_or_baseline_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout);runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);identity=next(row["evidence"] for row in result["ledger"] if row["phase"]=="verify-recreated-identities");self.assertEqual(identity["container_ids"],{"adguard":"8"*64,"adguard-exporter":"9"*64})
        for label,mutation in (("digest",lambda x:x["containers"][0].update(image_digest="sha256:"+"0"*64)),("baseline",lambda x:x["baseline"]["dns"]["lan_a"].update(status="SERVFAIL"))):
            with self.subTest(label=label),tempfile.TemporaryDirectory() as directory:
                contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,post_mutation=mutation);runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
                result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["status"],"recovery-failed");self.assertIn(result["failed_phase"],("verify-recreated-identities","smoke-test"));self.assertEqual(result["recovery"]["status"],"failed")
    def test_forward_and_rollback_image_references_are_channel_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);manifest=contract["manifest"]
            forward=copy.deepcopy(self.case.inventory);rollback=copy.deepcopy(self.case.inventory)
            for value in (forward,rollback):
                for index,item in enumerate(value["containers"]):item["id"]=("8" if index==0 else "9")*64
                value["volume"]["references"]=[next(item["id"] for item in value["containers"] if item["name"]=="adguard")]
            forward["servarr"].update(commit=manifest["revision_contract"]["forward"]["commit"],render_sha256=manifest["revision_contract"]["forward"]["render_sha256"])
            for item in forward["containers"]:item["image_ref"]=forward["servarr"]["render_semantics"]["images"][item["name"]]
            rollback["servarr"].update(commit=manifest["revision_contract"]["rollback"]["commit"],render_sha256=manifest["revision_contract"]["rollback"]["render_sha256"])
            self.e.validate_post(manifest,forward,"forward");self.e.validate_post(manifest,rollback,"rollback")
            with self.assertRaises(self.e.Drift):self.e.validate_post(manifest,rollback,"forward")
            rollback_as_forward=copy.deepcopy(forward);rollback_as_forward["servarr"].update(commit=manifest["revision_contract"]["rollback"]["commit"],render_sha256=manifest["revision_contract"]["rollback"]["render_sha256"])
            with self.assertRaises(self.e.Drift):self.e.validate_post(manifest,rollback_as_forward,"rollback")
    def test_snapshot_binding_and_new_post_observations_are_value_free(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout);manifest=contract["manifest"];post=POSTCHECK_MODULE._normalized_point(runner._post_inventory())
            self.assertEqual(set(runner.snapshot_binding(layout["config_snapshot"])),{"path","uuid"})
            scan={"containers":["adguard","adguard-exporter"],"fatal_matches":{"adguard":0,"adguard-exporter":0},"patterns_checked":4,"raw_logs_retained":False,"status":"passed","version":1};self.assertEqual(self.e.sanitize_startup_scan(scan),{"fatal_matches":{"adguard":0,"adguard-exporter":0},"patterns_checked":4,"status":"passed","version":1})
            for invalid in ({**scan,"fatal_matches":{"adguard":1,"adguard-exporter":0}},{**scan,"raw_logs":"forbidden"}):
                with self.assertRaises(self.e.Drift):self.e.sanitize_startup_scan(invalid)
            raw_observation={"duration_seconds":900,"end":copy.deepcopy(post),"raw_logs_retained":False,"sample_interval_seconds":30,"samples":31,"start":post,"status":"stable","version":1};observation=self.e.validate_observation(manifest,raw_observation);self.assertEqual(set(observation),{"duration_seconds","end_sha256","sample_interval_seconds","samples","start_sha256","status","version"});self.assertNotIn("containers",observation)
            full=runner._post_inventory();actual=POSTCHECK_MODULE.stable_observation("adguard,adguard-exporter",900,30,"full-normalized-start-end","exact-new-and-stable","exact","zero","discard",capture=lambda:copy.deepcopy(full),sleep=lambda _:None,clock=lambda:0);self.assertEqual(self.e.validate_observation(manifest,actual),observation)
            with self.assertRaises(self.e.Drift):self.e.validate_observation(manifest,{**raw_observation,"duration_seconds":899})
            changed=copy.deepcopy(raw_observation);changed["end"]["containers"]["adguard"]["id"]="a"*64
            with self.assertRaises(self.e.Drift):self.e.validate_observation(manifest,changed)
            phases=list(manifest["phases"]);commands=copy.deepcopy(manifest["commands"]);index=phases.index("record-rollback-evidence");phases[index:index]=["scan-startup-fatal-logs","observe-stable-15-minutes"];commands[index:index]=[["fixture-scan"],["fixture-observe","900"]];manifest["phases"]=phases;manifest["commands"]=commands;contract["manifest_sha256"]=self.case.t.digest(manifest);runner.render_sha=manifest["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["status"],"completed");scan=next(row["evidence"] for row in result["ledger"] if row["phase"]=="scan-startup-fatal-logs");observe=next(row["evidence"] for row in result["ledger"] if row["phase"]=="observe-stable-15-minutes");self.assertEqual(scan["fatal_matches"],{"adguard":0,"adguard-exporter":0});self.assertEqual(observe["status"],"stable");self.assertNotIn("start",observe);self.assertNotIn("end",observe)
    def test_recovery_failure_is_journaled_and_preserves_original_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,fail="archive-work-volume",recovery_fail=True);runner.render_sha="0"*64
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertTrue(result["recovery_failed"]);self.assertEqual(result["failed_phase"],"archive-work-volume");journal=[json.loads(line) for line in pathlib.Path(layout["journal"]).read_text().splitlines()];self.assertEqual(journal[-1]["event"],"recovery-recreate-exact-pair");self.assertEqual(journal[-1]["status"],"failed")
    def test_rollback_schema_mismatch_blocks_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            contract,layout=self.contract(directory);runner=Runner(self.case.inventory,layout,rollback={"unexpected":True});runner.render_sha=contract["manifest"]["resources"]["servarr"]["render_sha256"]
            result=self.e.execute(contract,contract["manifest_sha256"],runner,allow_unwired=True,allow_fixture_layout=True);self.assertEqual(result["status"],"failed");self.assertEqual(result["failed_phase"],"record-rollback-evidence")
    def test_no_shell_eval_cleanup_or_broad_restart(self):
        source=EXEC.read_text().lower()
        for token in ("shell=true","eval(","rm -rf","docker restart","docker prune","volume rm","unlink(layout[\"archive\"]"):
            self.assertNotIn(token,source)
        self.assertNotIn("tree(subtree)",source);self.assertNotIn("adguard_config_tree_sha256",source)
    def test_execute_cli_rejects_unwired_contract_before_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/"authorization.json";path.write_text(json.dumps(self.base,sort_keys=True,separators=(",",":")))
            env={**__import__("os").environ,"P2_ADGUARD_EXECUTOR_SOURCE":str(EXEC)};result=subprocess.run([sys.executable,EXEC,"execute",str(path),self.base["manifest_sha256"]],env=env,text=True,capture_output=True)
            self.assertEqual(result.returncode,1);self.assertEqual(result.stdout,"");self.assertEqual(result.stderr,"stateful-adguard-transition-exec: BLOCKED: Drift\n")
if __name__=="__main__":unittest.main()
