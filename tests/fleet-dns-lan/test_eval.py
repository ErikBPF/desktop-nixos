import json, pathlib, subprocess, unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]

def nix(*args,check=True):
    return subprocess.run(["nix",*args],cwd=ROOT,text=True,capture_output=True,check=check)

class FleetDnsEvalTest(unittest.TestCase):
    def value(self,host,path,raw=False):
        flag="--raw" if raw else "--json"
        output=nix("eval",flag,f".#nixosConfigurations.{host}.config.{path}").stdout
        return output if raw else json.loads(output)

    def test_generated_corefiles(self):
        kepler=self.value("kepler","services.coredns.config",True)
        self.assertIn("bind enp5s0",kepler);self.assertIn("template IN AAAA",kepler)
        self.assertIn("forward . 192.168.10.210 1.1.1.1 9.9.9.9",kepler)
        self.assertIn("policy sequential",kepler);self.assertNotIn("\n  log\n",kepler)
        vanguard=self.value("vanguard","services.coredns.config",True)
        self.assertIn("bind tailscale0",vanguard);self.assertIn("\n  log\n",vanguard)
        self.assertNotIn("policy sequential",vanguard)

    def test_firewall_and_service_are_interface_scoped(self):
        self.assertEqual(self.value("kepler","networking.firewall.interfaces.enp5s0.allowedTCPPorts"),[53])
        self.assertEqual(self.value("kepler","networking.firewall.interfaces.enp5s0.allowedUDPPorts"),[53])
        self.assertIn("network-online.target",self.value("kepler","systemd.services.coredns.after"))
        self.assertIn(53,self.value("vanguard","networking.firewall.interfaces.tailscale0.allowedTCPPorts"))
        self.assertIn(53,self.value("vanguard","networking.firewall.interfaces.tailscale0.allowedUDPPorts"))
        self.assertIn("tailscaled.service",self.value("vanguard","systemd.services.coredns.after"))

    def rejected(self,module):
        expression='''let f=builtins.getFlake (toString ./.); c=f.nixosConfigurations.kepler.extendModules { modules=[({lib,...}: { %s })]; }; in c.config.system.build.toplevel.drvPath'''%module
        result=nix("eval","--impure","--expr",expression,check=False)
        self.assertNotEqual(result.returncode,0,result.stdout)

    def test_invalid_interface_empty_and_public_first_are_rejected(self):
        self.rejected('services.fleetDns.interface = lib.mkForce "eth0";')
        self.rejected('services.fleetDns.upstream = lib.mkForce [];')
        self.rejected('services.fleetDns.upstream = lib.mkForce ["1.1.1.1" "9.9.9.9"];')

if __name__=="__main__":unittest.main()
