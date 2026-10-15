"""Offline acceptance: mock commands, never touch routes or services."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "probe", ROOT / "scripts/verify-roaming-dns.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
FLEET = json.loads((ROOT / "fleet.json").read_text())
IP = FLEET["hosts"]["discovery"]["ip"]
TAIL = FLEET["hosts"]["discovery"]["tailscaleIp"]
ZONE = FLEET["ingress"]["homelab"]["zone"]
HOME = IP.rsplit(".", 1)[0]
PREFIXES = [f"{HOME}.{n}/32" for n in (1, 2, 4)] + [f"{IP}/32"]


class RoamingProbe(unittest.TestCase):
    def test_success_requires_confirmed_off_lan_and_every_path_layer(self):
        def check(case, expected, intent=True):
            calls = []
            source = f"{HOME}.50" if case == "on-lan" else "10.115.78.213"
            subnet = f"{HOME}.0/24" if case == "on-lan" else "10.115.78.0/24"
            gateway = f"{HOME}.1" if case == "on-lan" else "10.115.78.127"

            def run(argv, **kwargs):
                calls.append(argv)
                self.assertLessEqual(kwargs["timeout"], 15)
                self.assertTrue(kwargs["capture_output"])
                if case == "timeout":
                    raise subprocess.TimeoutExpired(argv, kwargs["timeout"])
                if case == "path-timeout" and argv[0] == "dig":
                    raise subprocess.TimeoutExpired(argv, kwargs["timeout"])
                if argv[:5] == ["ip", "-j", "-4", "route", "show"]:
                    rows = [
                        {"dst": "default", "dev": "wlo1", "gateway": gateway,
                         "prefsrc": source},
                        {"dst": subnet, "dev": "wlo1", "protocol": "kernel",
                         "scope": "link", "prefsrc": source, "flags": []},
                        {"dst": "192.168.39.0/24", "dev": "virbr0", "protocol": "kernel",
                         "scope": "link", "prefsrc": "192.168.39.1", "flags": []},
                    ]
                    if case in ("static-home-route", "bridge-home-route"):
                        rows += [{"dst": f"{HOME}.0/24",
                                  "dev": "virbr0" if case == "bridge-home-route" else "wlo1",
                                  "protocol": "kernel" if case == "bridge-home-route" else "static",
                                  "scope": "link",
                                  "prefsrc": f"{HOME}.50", "flags": []}]
                    if case == "ambiguous":
                        rows += [{"dst": "172.16.0.0/24", "dev": "eno1",
                                  "protocol": "kernel", "scope": "link",
                                  "prefsrc": "172.16.0.2"}]
                    if case == "no-uplink":
                        rows = []
                    output = json.dumps(rows)
                elif argv[:4] == ["ip", "-j", "-4", "address"]:
                    interfaces = [
                        {"ifname": "wlo1", "flags": ["UP", "LOWER_UP"],
                         "operstate": "UP", "addr_info": [
                            {"family": "inet", "local": source, "prefixlen": 24,
                             "scope": "global"}]},
                        {"ifname": "eno1", "flags": ["UP", "LOWER_UP"],
                         "operstate": "UP", "addr_info": [
                            {"family": "inet", "local": "172.16.0.2",
                             "prefixlen": 24, "scope": "global"}]},
                        {"ifname": "virbr0", "flags": ["UP", "LOWER_UP"],
                         "operstate": "UP", "addr_info": [
                             {"family": "inet", "local": "192.168.39.1",
                              "prefixlen": 24, "scope": "global"}]},
                    ]
                    if case == "secondary-home-address":
                        interfaces[0]["addr_info"].append({
                            "family": "inet", "local": f"{HOME}.50", "prefixlen": 24,
                            "scope": "global"})
                    output = json.dumps(interfaces)
                elif argv[:5] == ["ip", "-j", "-4", "route", "get"]:
                    if case == "route-error" and argv[5] == IP:
                        raise subprocess.CalledProcessError(2, argv)
                    output = json.dumps([{"dst": argv[5], "dev":
                        "wlo1" if case == "wrong-route" and argv[5] == IP
                        else "tailscale0"}])
                elif argv == ["tailscale", "status", "--json"]:
                    peer = {"HostName": "other" if case == "wrong-hostname" else "discovery",
                            "TailscaleIPs": [TAIL]}
                    if case == "missing-hostname":
                        del peer["HostName"]
                    output = json.dumps({"Peer": {} if case == "missing-peer" else {"peer": peer}})
                elif argv[0] == "tailscale" or "tailscale" in argv:
                    if case == "netmap-denied" or (case == "operator-denied" and argv[0] == "tailscale"):
                        raise subprocess.CalledProcessError(1, argv)
                    allowed = PREFIXES[:-1] if case == "missing-route" else PREFIXES
                    output = json.dumps({"Peers": [{
                        "Addresses": [f"{TAIL}/32"], "AllowedIPs": allowed}]})
                elif argv[0] == "dig":
                    output = "203.0.113.9\n" if (
                        (case == "udp-dns" and "+tcp" not in argv) or
                        (case == "tcp-dns" and "+tcp" in argv)
                    ) else IP + "\n"
                elif argv[0] == "getent":
                    output = f"{IP} STREAM {argv[-1]}\n{IP} DGRAM\n{IP} RAW\n"
                    if case == "system-dns":
                        output = "203.0.113.9 STREAM\n"
                elif argv[0] == "curl":
                    self.assertEqual(argv[1], "--disable")
                    self.assertNotIn("--resolve", argv)
                    self.assertNotIn("-k", argv)
                    self.assertNotIn("--location", argv)
                    self.assertIn("--noproxy", argv)
                    self.assertIn("/dev/null", argv)
                    if case == "tls":
                        raise subprocess.CalledProcessError(60, argv)
                    code = "401" if "/v1/models" in argv[-1] else "302"
                    if case == "http-status":
                        code = "200"
                    output = f"{code} {IP if case != 'remote-ip' else '203.0.113.9'}"
                else:
                    self.fail(f"Unexpected command: {argv}")
                return subprocess.CompletedProcess(argv, 0, stdout=output, stderr="")

            output = io.StringIO()
            with patch.object(probe.subprocess, "run", side_effect=run, create=True), \
                    patch.object(Path, "exists", lambda path: "virbr0" not in str(path)), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = probe.main(["--off-lan"] if intent else [])
            self.assertEqual(code, expected, (case, output.getvalue()))
            self.assertEqual("ROAMING_DNS_OK" in output.getvalue(), expected == 0)
            if expected == 2:
                self.assertNotIn("OFF_LAN_VERIFIED", output.getvalue())
            if expected == 0:
                self.assertEqual(sum(c[0] == "dig" for c in calls), 2)
                self.assertEqual(sum(c[0] == "getent" for c in calls), 2)
                self.assertEqual(sum(c[0] == "curl" for c in calls), 2)
                self.assertEqual(sum(c[:5] == ["ip", "-j", "-4", "route", "get"]
                                     for c in calls), 4)
                self.assertIn(f"https://litellm.{ZONE}/v1/models", calls[-2])
                self.assertIn(f"https://adguard.{ZONE}/", calls[-1])
            return calls

        for case in ("missing-route", "wrong-route", "udp-dns", "tcp-dns",
                     "system-dns", "tls", "http-status", "remote-ip",
                     "route-error", "netmap-denied", "path-timeout",
                     "missing-peer", "wrong-hostname", "missing-hostname"):
            with self.subTest(case=case):
                check(case, 1)
        for case in ("on-lan", "ambiguous", "no-uplink", "timeout",
                     "secondary-home-address", "static-home-route", "bridge-home-route"):
            with self.subTest(case=case):
                check(case, 2)
        self.assertEqual(check("no-intent", 2, intent=False), [])
        check("healthy", 0)
        check("operator-denied", 0)


if __name__ == "__main__":
    unittest.main()
