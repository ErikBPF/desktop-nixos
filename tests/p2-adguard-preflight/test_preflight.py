import copy, importlib.util, os, pathlib, tempfile, unittest
from test_inventory import raw

ROOT=pathlib.Path(__file__).resolve().parents[2]
COLLECTOR=ROOT/"modules/hosts/discovery/_stateful-adguard-inventory.py";PLANNER=ROOT/"modules/hosts/discovery/_stateful-adguard-preflight.py"
JUSTFILE=ROOT/"justfile"
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

class PreflightTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.c=load(COLLECTOR,"collector");cls.p=load(PLANNER,"planner")
    def setUp(self):
        self.p.TARGET_COMMIT="c"*40;self.inventory=self.c.normalize(raw());self.p.TARGET_IMAGE_REFS=self.inventory["servarr"]["render_semantics"]["images"]
    def test_deterministic_hash_bound_preflight_only_manifest(self):
        first=self.p.envelope(self.p.plan(self.inventory));second=self.p.envelope(self.p.plan(copy.deepcopy(self.inventory)))
        self.assertEqual(first,second);self.p.verify(self.inventory,first)
        self.assertEqual(first["manifest"]["mode"],"preflight-only")
        self.assertFalse(first["manifest"]["approval_ready"]);self.assertEqual(first["manifest"]["blockers"],["backup_restore_evidence","secondary_dns_or_waiver"])
        self.assertEqual(first["manifest"]["actions"],["bind-existing-physical-volume","bind-dependent-container-identities","record-baseline-without-mutation"])
    def test_exact_drift_table_halts(self):
        authorization=self.p.envelope(self.p.plan(self.inventory))
        cases=[]
        for mutate in (lambda x:x["containers"].pop(),lambda x:x["containers"][0].update(image_digest="sha256:"+"0"*64),lambda x:x["containers"][0].update(mounts=[]),lambda x:x["containers"][0].update(networks=[]),lambda x:x["containers"][0].update(restart_count=1),lambda x:x["containers"][0]["compose_labels"].update(oneoff="True"),lambda x:x["volume"].update(ownership="0:0"),lambda x:x["volume"].update(references=["3"*64]),lambda x:x["volume"].update(name="discovery_adguard_work"),lambda x:x["protected_collision"].update(exists=False),lambda x:x["baseline"]["api"].update(user_rule_count=-1),lambda x:x["baseline"]["api"].update(protection_enabled=False),lambda x:x["servarr"].update(render_sha256="0"*64),lambda x:x["servarr"].update(render_contract={}),lambda x:x["servarr"].update(render_semantics={})):
            changed=copy.deepcopy(self.inventory);mutate(changed);cases.append(changed)
        for changed in cases:
            with self.assertRaises(self.p.Drift):self.p.verify(changed,authorization)
    def test_volatile_counts_do_not_change_authorization(self):
        first=self.p.envelope(self.p.plan(self.inventory));changed=copy.deepcopy(self.inventory);changed["baseline"]["api"]["stats"]["dns_queries"]+=99
        self.assertEqual(first,self.p.envelope(self.p.plan(changed)))
    def test_extra_or_privacy_field_halts(self):
        for path in (("baseline","api"),("containers",0)):
            changed=copy.deepcopy(self.inventory);node=changed
            for key in path:node=node[key]
            node["client_ip"]="192.0.2.1"
            with self.assertRaises(self.p.Drift):self.p.plan(changed)
    def test_pre_adoption_current_ref_and_repo_digest_are_exact(self):
        for name in ("adguard","adguard-exporter"):
            index=next(i for i,item in enumerate(self.inventory["containers"]) if item["name"]==name)
            for value in (self.p.TARGET_IMAGE_REFS[name],"example.invalid/other:tag"):
                changed=copy.deepcopy(self.inventory);changed["containers"][index]["image_ref"]=value
                with self.subTest(name=name,value=value),self.assertRaises(self.p.Drift):self.p.plan(changed)
            changed=copy.deepcopy(self.inventory);changed["containers"][index]["image_digest"]="sha256:"+"0"*64
            with self.subTest(name=name,digest="wrong"),self.assertRaises(self.p.Drift):self.p.plan(changed)
    def test_exporter_family_map_is_exact_private_and_diagnostic(self):
        for mutation in (lambda families:families.update(adguard_dns_queries=False),lambda families:families.update(unexpected_metric=True)):
            changed=copy.deepcopy(self.inventory);mutation(changed["baseline"]["exporter"]["families"])
            with self.assertRaises(self.p.Drift):self.p.plan(changed)
        rendered=str(self.p.plan(self.inventory)["baseline"]["exporter"])
        self.assertNotIn("metric_value",rendered);self.assertNotIn("labels",rendered)
    def test_planner_has_no_execution_surface(self):
        source=PLANNER.read_text().lower()
        for token in ("subprocess","docker stop","compose up","snapshot","archive","volume rm","prune","execute"):self.assertNotIn(token,source)

    def test_recipe_publication_is_atomic_no_clobber(self):
        source=JUSTFILE.read_text()
        for recipe,next_recipe in (("discovery-adguard-inventory output:","discovery-adguard-preflight inventory output:"),("discovery-adguard-preflight inventory output:","discovery-adguard-result inventory authorization:")):
            body=source.split(recipe,1)[1].split(next_recipe,1)[0]
            self.assertIn('ln "$tmp" "{{output}}"\n    rm "$tmp"',body)
            self.assertNotIn('mv "$tmp" "{{output}}"',body)
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);temporary=root/"output.tmp";output=root/"output"
            temporary.write_text("new");output.write_text("retained")
            with self.assertRaises(FileExistsError):os.link(temporary,output)
            self.assertEqual(output.read_text(),"retained")
            self.assertEqual(temporary.read_text(),"new")

if __name__=="__main__":unittest.main()
