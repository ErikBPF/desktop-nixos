import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT=pathlib.Path(__file__).resolve().parents[2]
SCRIPT=ROOT/"modules/hosts/discovery/_stateful-swag-transition-amendment.py"
BASE_TEST=ROOT/"tests/p1-swag-transition/test_transition.py"

def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def fixture():
    base=load(BASE_TEST,"transition_fixture").fixture()
    contract={"version":1,"cwd":"/home/erik/servarr/machines/discovery","argv":["docker-compose","--project-name","networking","--project-directory","/home/erik/servarr/machines/discovery","--env-file","/home/erik/servarr/machines/discovery/.env","--env-file","/run/vault-agent/networking.env","-f","/home/erik/servarr/machines/discovery/networking.yml","config","--no-interpolate","--no-env-resolution"]}
    return {"attempt_01":base["attempt_01"],"attempt_02":base["attempt_02"],"credential":{"absent":True,"path":"/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini","symlink":False},"old_journal":{"artifacts":{"authorization":{"path":"/var/lib/stateful-stack-migrations/p1-swag/transition-b676063/authorization.json","sha256":"a34e064ac10a529bba3a8157cef2692cb597dee2fcf25c36c64704b1f1b17ad4"},"observation":{"path":"/var/lib/stateful-stack-migrations/p1-swag/transition-b676063/observation.json","sha256":"b04c70cd83b841c28bdda82be09af92be275dfb19df03477f235c54efa68f1b2"}},"manifest_sha256":"426fa097cd4b6ce0e12609e25f64732dac0f1dacfb4dda8f1a3563f3cca854e4","phase_markers":[],"top_level_entries":["authorization.json","observation.json","phases"]},"repo":{"clean":True,"head":"b676063eafa53c00947c458d631493f98349f63c","origin_main":"b676063eafa53c00947c458d631493f98349f63c","render_contract":contract,"render_sha256":"282e5e26ab38926d8fcdb6aad74c836089a7d72e3f2e85f172932697e6d34887"},"runtime":base["runtime"]}

class AmendmentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.m=load(SCRIPT,"amendment")
    def test_deterministic_exact_bound_value_free_plan(self):
        obs=fixture(); auth=self.m.envelope(self.m.plan(obs))
        self.assertEqual(auth,self.m.envelope(self.m.plan(copy.deepcopy(obs)))); self.m.verify(obs,auth)
        self.assertEqual(auth["manifest"]["approval_scope"]["services"],["swag-init","swag"])
        self.assertIn("runtime-vault-env",auth["manifest"]["credential_rewrite_contract"])
        self.assertEqual(auth["manifest"]["phases"],["repo-target","init-complete","metadata-complete","swag-complete","validated"])
        self.assertEqual(auth["manifest"]["repo"]["render_contract"],self.m.RENDER_CONTRACT)
    def test_drift_table_rejected(self):
        obs=fixture(); auth=self.m.envelope(self.m.plan(obs))
        for path in (("old_journal","phase_markers"),("old_journal","manifest_sha256"),("repo","render_sha256"),("runtime","containers",0,"id"),("credential","absent")):
            changed=copy.deepcopy(obs); node=changed
            for key in path[:-1]: node=node[key]
            node[path[-1]]=False if path[-1]=="absent" else (["unexpected"] if isinstance(node[path[-1]],list) else "0"*64)
            with self.subTest(path=path),self.assertRaises(self.m.Drift): self.m.verify(changed,auth)
    def test_executor_has_no_repo_transition_and_is_resumable(self):
        source=SCRIPT.read_text()
        for forbidden in ("git fetch","git reset","git pull","docker system prune","docker volume rm"):
            self.assertNotIn(forbidden,source)
        for required in ("O_NOFOLLOW","repair_metadata","rename_noreplace","validate_completed","both container identities","--force-recreate"):
            self.assertIn(required,source)
        for required in ("supersedes_manifest_sha256","resume_origin","corrected_render_sha256","corrected_render_contract","base.git_run"):
            self.assertIn(required,source)

    def test_completed_metadata_allows_reboot_inode_change_only(self):
        recorded={"device":56,"inode":100,"uid":1000,"gid":1000,"mode":"0600","path":"/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini","regular":True,"symlink":False}
        rebooted=dict(recorded,device=57,inode=200)
        before=(dict(rebooted),dict(recorded))
        self.assertTrue(self.m.completed_metadata_valid(rebooted,recorded))
        self.assertEqual((rebooted,recorded),before)
        for key,value in (("uid",0),("gid",100),("mode","0644"),("regular",False),("symlink",True),("path","/tmp/cloudflare.ini")):
            changed=dict(rebooted);changed[key]=value
            with self.subTest(key=key):self.assertFalse(self.m.completed_metadata_valid(changed,recorded))
        malformed=[]
        for side in ("current","recorded"):
            for key,value in (("device",-1),("inode",-1),("device",True),("inode",False)):
                current,stored=dict(rebooted),dict(recorded)
                (current if side=="current" else stored)[key]=value
                malformed.append((side,key,current,stored))
            current,stored=dict(rebooted),dict(recorded)
            del (current if side=="current" else stored)["inode"]
            malformed.append((side,"missing",current,stored))
        stored_bad=dict(recorded,gid=100)
        malformed.append(("recorded","stable",dict(rebooted),stored_bad))
        current_bad=dict(rebooted,regular=1)
        malformed.append(("current","bool-type",current_bad,dict(recorded)))
        for side,key,current,stored in malformed:
            with self.subTest(side=side,key=key):self.assertFalse(self.m.completed_metadata_valid(current,stored))

    def test_validate_completed_accepts_reboot_inode_without_any_mutation(self):
        observation=fixture(); approved="9"*64
        final=copy.deepcopy(observation["runtime"])
        for index,item in enumerate(final["containers"],start=1):item["id"]=str(index)*64
        recorded={"device":56,"inode":100,"uid":1000,"gid":1000,"mode":"0600","path":"/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini","regular":True,"symlink":False}
        current=dict(recorded,device=57,inode=200)
        with tempfile.TemporaryDirectory() as directory:
            evidence=pathlib.Path(directory)
            png=b"\x89PNG\r\n\x1a\nfixture"
            (evidence/"kindle.png").write_bytes(png)
            result={"corrected_render_contract":self.m.RENDER_CONTRACT,"corrected_render_sha256":self.m.RENDER,"kindle_png_sha256":self.m.hashlib.sha256(png).hexdigest(),"manifest_sha256":approved,"resume_origin":"post-reset-pre-phase","runtime_sha256":self.m.hashlib.sha256(self.m.canonical(final)).hexdigest(),"status":"passed","supersedes_manifest_sha256":self.m.OLD_MANIFEST,"version":1}
            (evidence/"final-runtime.json").write_text(json.dumps(final))
            (evidence/"metadata-state.json").write_text(json.dumps(recorded))
            (evidence/"result.json").write_text(json.dumps(result))
            forbidden=mock.Mock(side_effect=AssertionError("completed path mutated state"))
            with mock.patch.object(self.m,"NEW",evidence), mock.patch.object(self.m,"verify_repo"), mock.patch.object(self.m,"runtime",return_value=final), mock.patch.object(self.m.base,"metadata",return_value=current), mock.patch.object(self.m.base,"validate_gates"), mock.patch.object(self.m,"persist_exact",forbidden), mock.patch.object(self.m,"mark",forbidden), mock.patch.object(self.m.base,"repair_metadata",forbidden), mock.patch.object(self.m.base,"write_json",forbidden), mock.patch.object(self.m.base,"write_bytes",forbidden), mock.patch.object(self.m.base,"run",forbidden):
                self.assertEqual(self.m.validate_completed(observation,approved),result)
            forbidden.assert_not_called()

if __name__=="__main__": unittest.main()
