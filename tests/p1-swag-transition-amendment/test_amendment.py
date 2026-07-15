import copy
import importlib.util
import pathlib
import unittest

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

if __name__=="__main__": unittest.main()
