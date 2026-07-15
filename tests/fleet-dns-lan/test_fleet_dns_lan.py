import pathlib, re, unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
MODULE=(ROOT/"modules/services/fleet-dns.nix").read_text()
KEPLER=(ROOT/"modules/hosts/kepler/default.nix").read_text()
VANGUARD=(ROOT/"modules/hosts/vanguard/default.nix").read_text()

class FleetDnsLanTest(unittest.TestCase):
    def test_interface_option_defaults_to_vanguard_tailnet(self):
        self.assertRegex(MODULE,r'interface\s*=\s*lib\.mkOption\s*\{[^}]*default\s*=\s*"tailscale0";')
        self.assertIn('bind ${cfg.interface}',MODULE)
        self.assertRegex(MODULE,r'networking\.firewall\.interfaces\.\$\{cfg\.interface\}\s*=\s*\{[^}]*allowedTCPPorts\s*=\s*\[53\];[^}]*allowedUDPPorts\s*=\s*\[53\];')
        self.assertNotRegex(MODULE,r'networking\.firewall\.allowed(?:TCP|UDP)Ports\s*=')

    def test_sequential_forward_is_opt_in_and_kepler_orders_adguard_first(self):
        self.assertRegex(MODULE,r'sequentialUpstream\s*=\s*lib\.mkEnableOption')
        self.assertIn('lib.optionalString (!cfg.sequentialUpstream)',MODULE)
        self.assertIn('lib.optionalString cfg.sequentialUpstream',MODULE)
        self.assertIn('policy sequential',MODULE)
        self.assertIn('m.nixos.fleet-dns',KEPLER)
        self.assertRegex(KEPLER,r'services\.fleetDns\s*=\s*\{[^}]*enable\s*=\s*true;[^}]*interface\s*=\s*"enp5s0";[^}]*upstream\s*=\s*\["192\.168\.10\.210"\s+"1\.1\.1\.1"\s+"9\.9\.9\.9"\];[^}]*sequentialUpstream\s*=\s*true;')

    def test_vanguard_keeps_default_tailnet_behavior(self):
        self.assertIn('services.fleetDns.enable = true;',VANGUARD)
        self.assertNotRegex(VANGUARD,r'services\.fleetDns\.(?:interface|upstream|sequentialUpstream)')

    def test_fleet_zones_remain_locally_synthesized(self):
        self.assertIn('template IN A',MODULE)
        self.assertIn('template IN AAAA',MODULE)
        self.assertIn('rcode NOERROR',MODULE)
        self.assertIn('fleet.hosts.${ingress.host}.ip',MODULE)

    def test_query_logging_defaults_on_but_kepler_disables_it(self):
        self.assertRegex(MODULE,r'queryLog\s*=\s*lib\.mkOption\s*\{[^}]*default\s*=\s*true;')
        self.assertIn('lib.optionalString cfg.queryLog "log"',MODULE)
        self.assertIn('queryLog = false;',KEPLER)

    def test_unknown_or_wildcard_interface_is_not_allowed(self):
        self.assertIn('lib.types.enum ["tailscale0" "enp5s0"]',MODULE)
        option=MODULE.split('interface = lib.mkOption {',1)[1].split('};',1)[0]
        self.assertNotIn('0.0.0.0',option);self.assertNotIn('"*"',option)

    def test_empty_upstream_is_rejected(self):
        self.assertIn('cfg.upstream != []',MODULE)

    def test_sequential_public_first_or_missing_fallback_is_rejected(self):
        self.assertRegex(MODULE,r'builtins\.length cfg\.upstream\s*>= 2')
        self.assertIn('builtins.head cfg.upstream == fleet.hosts.discovery.ip',MODULE)
        self.assertIn('!cfg.sequentialUpstream',MODULE)

    def test_startup_waits_for_the_selected_interface_owner(self):
        self.assertIn('if cfg.interface == "tailscale0"',MODULE)
        self.assertIn('["tailscaled.service"]',MODULE)
        self.assertIn('["network-online.target"]',MODULE)
        self.assertIn('wants = lib.optional (cfg.interface != "tailscale0") "network-online.target";',MODULE)

if __name__=="__main__":unittest.main()
