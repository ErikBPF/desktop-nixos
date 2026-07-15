import os,pathlib,stat,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2];CALLBACK=ROOT/"scripts/p3-udhcpc-capture.sh"
class CallbackTest(unittest.TestCase):
 def invoke(self,event="bound",subnet="255.255.255.0",router="192.168.10.1",dns="192.168.10.210 192.168.10.230"):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);log=root/"ip.log";capture=root/"lease"
   fake=root/"ip";fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$IP_LOG"\n');fake.chmod(0o755)
   env=os.environ|{"PATH":f"{root}:{os.environ['PATH']}","IP_LOG":str(log),"P3_DHCP_CAPTURE":str(capture),"interface":"probe0","ip":"192.168.10.99","subnet":subnet,"router":router,"dns":dns}
   result=subprocess.run([CALLBACK,event],text=True,capture_output=True,env=env)
   return result,log.read_text() if log.exists() else "",capture.read_text() if capture.exists() else None,stat.S_IMODE(capture.stat().st_mode) if capture.exists() else None,list(root.glob("lease.tmp.*"))
 def test_bound_configures_namespace_and_atomically_preserves_dns_order(self):
  result,log,capture,mode,tmp=self.invoke();self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn("address replace 192.168.10.99/24 dev probe0",log);self.assertIn("route replace default via 192.168.10.1 dev probe0",log)
  self.assertEqual(capture,"event=bound dns=192.168.10.210 192.168.10.230\n");self.assertEqual(mode,0o600);self.assertEqual(tmp,[])
 def test_renew_is_allowed_but_multi_router_and_invalid_mask_fail_closed(self):
  self.assertEqual(self.invoke(event="renew")[0].returncode,0)
  self.assertNotEqual(self.invoke(router="192.168.10.1 192.168.10.2")[0].returncode,0)
  self.assertNotEqual(self.invoke(subnet="255.0.255.0")[0].returncode,0)
 def test_deconfig_flushes_only_interface_and_emits_no_record(self):
  result,log,capture,_,_=self.invoke(event="deconfig");self.assertEqual(result.returncode,0)
  self.assertEqual(log,"address flush dev probe0\n");self.assertIsNone(capture)
if __name__=="__main__":unittest.main()
