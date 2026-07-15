import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2];SCRIPT=ROOT/"scripts/p3-generic-dhcp-client.sh"
class Test(unittest.TestCase):
 def run_case(self,dns="192.168.10.210 192.168.10.230",lease=0,carrier="1",wireless=False,links="",uid="0",callback_uid="0",mode="755",route_dev="eno1",drift=False):
  with tempfile.TemporaryDirectory() as d:
   r=pathlib.Path(d);log=r/"ip.log";sys=r/"sys"/"eno1";sys.mkdir(parents=True);(sys/"carrier").write_text(carrier)
   if wireless:(sys/"wireless").mkdir()
   cb=ROOT/"scripts/p3-udhcpc-capture.sh"
   ud=r/"udhcpc";ud.write_text(f'''#!/bin/sh
cb="";interface_name=""; while [ "$#" -gt 0 ];do [ "$1" = -s ]&&cb=$2&&shift;[ "$1" = -i ]&&interface_name=$2&&shift;shift;done
interface=${{interface_name:-probe}} ip=192.168.10.99 subnet=255.255.255.0 router=192.168.10.1 dns={dns!r} "$cb" bound;exit {lease}
''');ud.chmod(0o755)
   (r/"id").write_text('#!/bin/sh\necho "$MOCK_UID"\n');(r/"id").chmod(0o755)
   (r/"stat").write_text('#!/bin/sh\n[ "$2" = %u ]&&echo "$MOCK_STAT_UID"||echo "$MOCK_MODE"\n');(r/"stat").chmod(0o755)
   ip=r/"ip";ip.write_text('''#!/bin/sh
echo "$*" >> "$IP_LOG"
case "$*" in
 "-j -4 route get 192.168.10.1") printf '[{"dst":"192.168.10.1","dev":"%s"}]\n' "$MOCK_ROUTE_DEV";;
 "-j address show dev eno1") if [ "$MOCK_DRIFT" = 1 ]&&grep -q 'netns delete' "$IP_LOG";then echo '[{"ifname":"eno1","address":"changed","mtu":1500,"flags":["UP"],"addr_info":[{"family":"inet","local":"192.168.10.50","prefixlen":24,"scope":"global","label":"eno1"}]}]';else echo '[{"ifname":"eno1","address":"00:11:22:33:44:55","mtu":1500,"flags":["UP"],"addr_info":[{"family":"inet","local":"192.168.10.50","prefixlen":24,"scope":"global","label":"eno1"}]}]';fi;;
 "-j route show table all dev eno1") echo '[{"dst":"default"}]';;
 "netns list") :;;
 -n*" -o link show") name=$(awk '/link add link/{for(i=1;i<=NF;i++)if($i=="name")print $(i+1)}' "$IP_LOG"|tail -1); if [ -n "$MOCK_LINKS" ];then printf '%b' "$MOCK_LINKS";else printf '1: lo: x\n2: %s@if3: x\n' "$name";fi;;
 netns\\ exec*) shift 3; if [ "$1" = dig ];then case " $* " in *" AAAA ") echo 'status: NOERROR, ANSWER: 0';; *"p3-nonexistent.invalid"*) echo 'status: NXDOMAIN';; *) echo 'status: NOERROR, ANSWER: 1 192.168.10.210';;esac;else exec "$@";fi;;
esac
''');ip.chmod(0o755)
   env=os.environ|{"PATH":f"{r}:{os.environ['PATH']}","IP_LOG":str(log),"P3_SYS_CLASS_NET":str(r/"sys"),"MOCK_LINKS":links,"MOCK_UID":uid,"MOCK_STAT_UID":callback_uid,"MOCK_MODE":mode,"MOCK_ROUTE_DEV":route_dev,"MOCK_DRIFT":"1" if drift else "0"}
   result=subprocess.run([SCRIPT,"eno1",ud,cb],text=True,capture_output=True,env=env)
   return result,log.read_text() if log.exists() else ""
 def test_exact_and_bounded_flags_cleanup_and_probes(self):
  x,log=self.run_case();self.assertEqual(x.returncode,0,x.stderr);self.assertEqual(x.stdout,"dhcp_dns=192.168.10.210,192.168.10.230\n")
  for token in ("address 02:","-T 3 -t 4 -A 2 -O dns","+tcp"," AAAA","p3-arbitrary.homelab.pastelariadev.com","p3-nonexistent.invalid","netns delete","netns list"):self.assertIn(token,log)
 def test_bad_dns_and_lease_cleanup(self):
  for dns,lease in [("192.168.10.230 192.168.10.210",0),("192.168.10.210",0),("192.168.10.210 1.1.1.1",0),("192.168.10.210 192.168.10.230",1)]:
   x,log=self.run_case(dns,lease);self.assertNotEqual(x.returncode,0);self.assertIn("netns delete",log)
 def test_carrier_wireless_and_overlay_rejected(self):
  self.assertNotEqual(self.run_case(carrier="0")[0].returncode,0);self.assertNotEqual(self.run_case(wireless=True)[0].returncode,0)
  x,log=self.run_case(links="1: lo: x\\n2: bad0: x\\n");self.assertNotEqual(x.returncode,0);self.assertIn("netns delete",log)
 def test_root_callback_route_and_parent_snapshot_gates(self):
  for kwargs in ({"uid":"1000"},{"callback_uid":"1000"},{"mode":"775"},{"route_dev":"wlan0"},{"drift":True}):
   with self.subTest(kwargs=kwargs):self.assertNotEqual(self.run_case(**kwargs)[0].returncode,0)
 def test_source_does_not_mutate_host_network(self):
  s=SCRIPT.read_text();self.assertNotIn("/etc/resolv.conf",s);self.assertNotIn("ip route add",s);self.assertIn('"$(id -u)" -eq 0',s)
if __name__=="__main__":unittest.main()
