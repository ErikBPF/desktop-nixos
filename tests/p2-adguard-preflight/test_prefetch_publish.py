import hashlib
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest


ROOT=pathlib.Path(__file__).resolve().parents[2];SOURCE=ROOT/"modules/hosts/discovery/_stateful-adguard-prefetch-publish.py"
def load():spec=importlib.util.spec_from_file_location("publisher",SOURCE);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def envelope():
    forward={"commit":"9969e35dca0cfb49a68bda3ba10156667cd4b53f","render_sha256":"b"*64,"tree":"64d61bb25e0ee7cadda556e54ec86c4faf4f1fd8"};rollback={"commit":"b676063eafa53c00947c458d631493f98349f63c","render_sha256":"e"*64,"tree":"d312855e4a501995cb3f0216659d63763c6b3205"}
    contract={"fetch_ref":"main","forward":forward,"remote":"origin","repository":"/home/erik/servarr","rollback":rollback,"version":1};evidence={"fetched_origin_main":forward["commit"],"forward":forward,"objects_present":True,"rollback":rollback,"version":1}
    return {"contract":contract,"contract_sha256":hashlib.sha256(canonical(contract)).hexdigest(),"evidence":evidence,"evidence_sha256":hashlib.sha256(canonical(evidence)).hexdigest()}
class PublisherTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.m=load()
    def fixture(self,directory):
        root=pathlib.Path(directory);pending=root/"pending";retained=root/"retained";retained.mkdir();pending.write_bytes(canonical(envelope())+b"\n");pending.chmod(0o600);return pending,retained/".publish",retained/"final",retained
    def publish(self,paths,hook=None):
        pending,staging,final,directory=paths;return self.m._publish(pending,staging,final,directory,os.getuid(),os.getgid(),hook=hook)
    def test_publish_exact_bytes_mode_and_no_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            paths=self.fixture(directory);expected=paths[0].read_bytes();self.publish(paths);self.assertEqual(paths[2].read_bytes(),expected);self.assertEqual(paths[2].stat().st_mode&0o777,0o600);self.assertFalse(paths[1].exists())
    def test_preexisting_final_and_staging_are_never_overwritten_or_deleted(self):
        for index in (1,2):
            with self.subTest(index=index),tempfile.TemporaryDirectory() as directory:
                paths=self.fixture(directory);paths[index].write_bytes(b"retained");
                with self.assertRaises(self.m.PublishError):self.publish(paths)
                self.assertEqual(paths[index].read_bytes(),b"retained")
    def test_symlink_wrong_mode_owner_schema_hash_and_noncanonical_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            paths=self.fixture(directory);target=paths[0].with_name("target");paths[0].replace(target);paths[0].symlink_to(target)
            with self.assertRaises(self.m.PublishError):self.publish(paths)
        for mutate in (lambda p:p.chmod(0o640),lambda p:p.write_text("{}\n"),lambda p:p.write_bytes(json.dumps(envelope(),indent=2).encode()+b"\n")):
            with tempfile.TemporaryDirectory() as directory:
                paths=self.fixture(directory);mutate(paths[0])
                with self.assertRaises(self.m.PublishError):self.publish(paths)
                self.assertFalse(paths[2].exists())
        with tempfile.TemporaryDirectory() as directory:
            paths=self.fixture(directory)
            with self.assertRaises(self.m.PublishError):self.m._publish(*paths,os.getuid()+1,os.getgid())
            self.assertFalse(paths[2].exists())
    def test_source_swap_after_open_publishes_validated_inode_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            paths=self.fixture(directory);expected=paths[0].read_bytes()
            def hook(stage):
                if stage=="after-open":
                    replacement=paths[0].with_name("replacement");replacement.write_bytes(b"attacker");replacement.chmod(0o600);os.replace(replacement,paths[0])
            self.publish(paths,hook);self.assertEqual(paths[2].read_bytes(),expected)
    def test_strict_semantic_types_identities_and_formats_rejected(self):
        mutations=(lambda v:v["contract"].update(version=True),lambda v:v["evidence"].update(version="1"),lambda v:v["contract"].update(repository="secret=value"),lambda v:v["contract"].update(remote="upstream"),lambda v:v["contract"].update(fetch_ref="release"),lambda v:v["evidence"].update(objects_present=1),lambda v:v["evidence"].update(fetched_origin_main="0"*40),lambda v:v["contract"]["forward"].update(commit="0"*40),lambda v:v["contract"]["rollback"].update(tree="0"*40),lambda v:v["contract"]["forward"].update(render_sha256="A"*64),lambda v:v.update(contract_sha256=1))
        for mutate in mutations:
            with self.subTest(mutate=mutate),tempfile.TemporaryDirectory() as directory:
                paths=self.fixture(directory);value=envelope();mutate(value)
                if isinstance(value.get("contract_sha256"),str):value["contract_sha256"]=hashlib.sha256(canonical(value["contract"])).hexdigest()
                value["evidence_sha256"]=hashlib.sha256(canonical(value["evidence"])).hexdigest();paths[0].write_bytes(canonical(value)+b"\n")
                with self.assertRaises(self.m.PublishError):self.publish(paths)
                self.assertFalse(paths[2].exists())
    def test_oversized_pending_rejected_before_read(self):
        with tempfile.TemporaryDirectory() as directory:
            paths=self.fixture(directory);paths[0].write_bytes(b"x"*(self.m.MAX_BYTES+1));paths[0].chmod(0o600)
            with self.assertRaises(self.m.PublishError):self.publish(paths)
            self.assertFalse(paths[2].exists())
    def test_failure_injection_cleans_only_owned_staging_and_retains_linked_final(self):
        for stage,final_expected in (("after-staging-write",False),("after-link",True),("after-unlink",True)):
            with self.subTest(stage=stage),tempfile.TemporaryDirectory() as directory:
                paths=self.fixture(directory)
                def hook(actual):
                    if actual==stage:raise RuntimeError("injected")
                with self.assertRaises(RuntimeError):self.publish(paths,hook)
                self.assertFalse(paths[1].exists());self.assertEqual(paths[2].exists(),final_expected)
if __name__=="__main__":unittest.main()
