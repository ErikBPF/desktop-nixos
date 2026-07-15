import pathlib, subprocess, tempfile, time, unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]

def package(name):
    output=subprocess.run(["nix","build","--no-link","--print-out-paths",f"nixpkgs#{name}"],cwd=ROOT,text=True,capture_output=True,check=True).stdout
    return [pathlib.Path(line) for line in output.splitlines()]

def executable(package_name,program):
    matches=[root/"bin"/program for root in package(package_name) if (root/"bin"/program).exists()]
    if len(matches)!=1:raise RuntimeError(f"expected one packaged {program} executable")
    return matches[0]

class CoreDnsRuntimeTest(unittest.TestCase):
    def test_packaged_coredns_udp_tcp_a_aaaa_nodata_and_nxdomain(self):
        coredns=executable("coredns","coredns")
        dig=executable("bind","dig")
        corefile='''homelab.pastelariadev.com:10553 {
  bind 127.0.0.1
  template IN A {
    answer "{{ .Name }} 300 IN A 192.168.10.210"
  }
  template IN AAAA {
    rcode NOERROR
  }
}
invalid:10553 {
  bind 127.0.0.1
  template ANY ANY {
    rcode NXDOMAIN
  }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/"Corefile";path.write_text(corefile)
            process=subprocess.Popen([coredns,"-conf",path],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
            try:
                for _ in range(30):
                    probe=subprocess.run([dig,"+time=1","+tries=1","@127.0.0.1","-p","10553","test.homelab.pastelariadev.com","A"],text=True,capture_output=True)
                    if probe.returncode==0:break
                    if process.poll() is not None:self.fail(process.stderr.read())
                    time.sleep(.1)
                self.assertIn("192.168.10.210",probe.stdout)
                tcp=subprocess.run([dig,"+tcp","+time=1","+tries=1","@127.0.0.1","-p","10553","test.homelab.pastelariadev.com","A"],text=True,capture_output=True,check=True)
                self.assertIn("192.168.10.210",tcp.stdout)
                aaaa=subprocess.run([dig,"+time=1","+tries=1","@127.0.0.1","-p","10553","test.homelab.pastelariadev.com","AAAA"],text=True,capture_output=True,check=True)
                self.assertIn("status: NOERROR",aaaa.stdout);self.assertIn("ANSWER: 0",aaaa.stdout)
                missing=subprocess.run([dig,"+time=1","+tries=1","@127.0.0.1","-p","10553","missing.invalid","A"],text=True,capture_output=True,check=True)
                self.assertIn("status: NXDOMAIN",missing.stdout)
            finally:
                process.terminate();process.wait(timeout=5);process.stderr.close()

if __name__=="__main__":unittest.main()
