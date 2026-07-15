import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"
OBSERVE = ROOT / "scripts/p3-adguard-outage-observe.sh"
CLIENT = ROOT / "scripts/p3-adguard-outage-client.sh"
CALLBACK = ROOT / "scripts/p3-udhcpc-capture.sh"
NAMES = ("adguard", "adguard-exporter", "k8s-apiserver", "swag", "swag-init")


def executable(path, text):
    path.write_text("#!/bin/sh\n" + text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def raw_containers():
    result = []
    for index, name in enumerate(NAMES):
        running = name != "swag-init"
        result.append({"Id": chr(97 + index) * 64, "Name": "/" + name,
            "Config": {"Image": f"registry.invalid/{name}@sha256:" + chr(102 - index) * 64,
                "Labels": {"com.docker.compose.project": "networking", "com.docker.compose.service": name,
                    "com.docker.compose.project.working_dir": "/home/erik/servarr/machines/discovery"}},
            "Image": "sha256:" + chr(102 - index) * 64,
            "State": {"Status": "running" if running else "exited", "ExitCode": 0,
                "Health": {"Status": "healthy"} if running and name != "adguard-exporter" else None},
            "RestartCount": 0, "HostConfig": {"RestartPolicy": {"Name": "unless-stopped", "MaximumRetryCount": 0}},
            "NetworkSettings": {"Networks": {"homelab-net": {"Aliases": [name], "IPAddress": "172.30.0.2", "GlobalIPv6Address": ""}}},
            "Mounts": [{"Type": "bind", "Source": f"/srv/{name}", "Destination": "/config", "Mode": "ro", "RW": False, "Propagation": "rprivate"}]})
    return result


def observation(containers):
    projected = []
    for item in containers:
        name = item["Name"][1:]
        projected.append({"id": item["Id"], "name": name, "project": "networking", "service": name,
            "working_dir": "/home/erik/servarr/machines/discovery", "image_id": item["Image"],
            "image_ref": item["Config"]["Image"], "state": item["State"]["Status"], "exit_code": 0,
            "health": (item["State"].get("Health") or {}).get("Status"), "restart_count": 0,
            "restart_policy": item["HostConfig"]["RestartPolicy"],
            "networks": [{"name": "homelab-net", "aliases": [name], "ip_address": "172.30.0.2", "global_ipv6_address": ""}],
            "mounts": [{"type": "bind", "name": None, "source": f"/srv/{name}", "destination": "/config", "driver": None, "mode": "ro", "rw": False, "propagation": "rprivate"}]})
    return {"client": {"interface": "p3d1234", "namespace": "p3-dhcp-proof", "overlays": [], "persistent_macvlan": True},
        "containers": sorted(projected, key=lambda x: x["name"]), "failover_bound_ms": 5000,
        "ipv6": {"default_route": {"dev": "p3d1234", "dst": "default", "gateway": "fe80::1", "protocol": "ra"},
            "prefix": "2001:db8:10::/64", "rdnss": "2001:db8:10::53", "rdnss_lifetime": "positive",
            "router": "fe80::1", "router_lifetime": "positive"},
        "probe_contract": {"filter_template": "{nonce}.doubleclick.net A",
            "fleet_templates": ["{nonce}.homelab.pastelariadev.com A", "{nonce}.homelab.pastelariadev.com AAAA"],
            "negative_template": "{nonce}.invalid A", "public_templates": ["{nonce}.1-1-1-1.sslip.io A", "{nonce}.2606-4700-4700--1111.sslip.io AAAA"],
            "resolvers": ["gateway", "adguard", "kepler", "system"], "transports": ["udp", "tcp"]},
        "probe_evidence": {"classifications_sha256": "0" * 64, "nonce_sha256": "1" * 64,
            "qnames_sha256": "2" * 64, "results_sha256": "3" * 64},
        "remote": {"ip": "192.168.10.210", "recovery_by_ip": True},
        "resolvers": {"nameservers": ["2001:db8:10::53", "192.168.10.210", "192.168.10.230"],
            "options": ["timeout:2", "attempts:1"]}, "version": 3}


class HardenedContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name); self.known = self.root / "known_hosts"; self.known.write_text("[192.168.10.210]:2222 key\n");self.known.chmod(0o400)
        self.rdisc = self.root / "rdisc6"; executable(self.rdisc, r'''case "$RA_MODE" in
 extra-router) extra='from fe80::2';; extra-rdnss) extra='Recursive DNS server : 2001:db8:10::54';;
 zero-router) router_lifetime=0;; zero-rdnss) dns_lifetime=0;; toolfail) exit 1;; timeout) exit 124;; esac
printf 'from fe80::1\nPrefix : 2001:db8:10::/64\nRecursive DNS server : 2001:db8:10::53\nRouter lifetime : %s seconds\nDNS server lifetime : %s seconds\n%s\n' "${router_lifetime:-1800}" "${dns_lifetime:-1200}" "${extra:-}"
''')
        self.obs_json = self.root / "observation.json"; self.obs_json.write_text(json.dumps(observation(raw_containers())))
        self.fake_observer = self.root / "observer"; executable(self.fake_observer, '''[ -n "${OBSERVER_CALLED:-}" ] && touch "$OBSERVER_CALLED"
if [ "$POST_DRIFT" = 1 ] && [ -e "$RESTORED" ];then jq '.containers |= map(if .name=="swag" then .image_ref="drift" else . end)|.probe_evidence.nonce_sha256=("4"*64)|.probe_evidence.qnames_sha256=("5"*64)|.probe_evidence.results_sha256=("6"*64)' "$OBS_JSON"
elif [ "${STALE_NONCE:-0}" = 1 ];then cat "$OBS_JSON"
elif [ "${FRESH_DRIFT:-}" = rdnss ];then jq '.ipv6.rdnss="2001:db8:10::54"|.probe_evidence.nonce_sha256=("4"*64)|.probe_evidence.qnames_sha256=("5"*64)|.probe_evidence.results_sha256=("6"*64)' "$OBS_JSON"
elif [ "${FRESH_DRIFT:-}" = order ];then jq '.resolvers.nameservers|=reverse|.probe_evidence.nonce_sha256=("4"*64)|.probe_evidence.qnames_sha256=("5"*64)|.probe_evidence.results_sha256=("6"*64)' "$OBS_JSON"
else jq '.probe_evidence.nonce_sha256=("4"*64)|.probe_evidence.qnames_sha256=("5"*64)|.probe_evidence.results_sha256=("6"*64)' "$OBS_JSON";fi
''')
        self.fake_client = self.root / "client"; executable(self.fake_client, "exit 0\n")
        self.fake_callback = self.root / "callback"; executable(self.fake_callback, "exit 0\n")

    def drill(self, *tail, env=None):
        args = [DRILL, *tail, self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback]
        return subprocess.run(args, text=True, capture_output=True, env=(os.environ | {"OBS_JSON": str(self.obs_json), "POST_DRIFT": "0", "RESTORED": str(self.root / "restored")} | (env or {})))

    def test_udhcpc_deconfig_flushes_ipv4_only_and_requires_interface(self):
        ip_log = self.root / "ip.log"
        fake_ip = self.root / "ip"
        executable(fake_ip, 'printf "%s\\n" "$*" >> "$IP_LOG"\n')
        env = os.environ | {"PATH": f"{self.root}:{os.environ['PATH']}", "IP_LOG": str(ip_log), "interface": "p3d1234"}
        result = subprocess.run([CALLBACK, "deconfig"], text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ip_log.read_text().splitlines(), ["-4 address flush dev p3d1234"])
        self.assertNotIn("address flush dev p3d1234", ip_log.read_text().splitlines())
        missing = subprocess.run([CALLBACK, "deconfig"], text=True, capture_output=True, env=env | {"interface": ""})
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(ip_log.read_text().splitlines(), ["-4 address flush dev p3d1234"])

    def test_manifest_v3_binds_inventory_and_all_implementations(self):
        result = self.drill("plan"); self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout); manifest = value["manifest"]
        self.assertEqual(manifest["version"], 3); self.assertEqual(set(manifest["bindings"]), {"client_sha256", "observer_sha256", "drill_sha256", "callback_sha256", "known_hosts_sha256", "rdisc6_sha256"})
        self.assertRegex(manifest["network_contract_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(manifest["probe_evidence"], observation(raw_containers())["probe_evidence"])
        canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":")); self.assertEqual(value["manifest_sha256"], hashlib.sha256(canonical.encode()).hexdigest())
        original = value["manifest_sha256"]
        changed = observation(raw_containers()); changed["probe_evidence"]["results_sha256"] = "5" * 64
        self.obs_json.write_text(json.dumps(changed)); self.assertNotEqual(original, json.loads(self.drill("plan").stdout)["manifest_sha256"])
        self.obs_json.write_text(json.dumps(observation(raw_containers())))
        old = value["manifest_sha256"]; self.known.chmod(0o600);self.known.write_text("changed\n");self.known.chmod(0o400); self.assertNotEqual(old, json.loads(self.drill("plan").stdout)["manifest_sha256"])
        self.known.chmod(0o600); self.assertNotEqual(self.drill("plan").returncode, 0); self.known.chmod(0o400)
        target = self.root / "known-target"; self.known.rename(target); self.known.symlink_to(target); self.assertNotEqual(self.drill("plan").returncode, 0)

    def test_rdisc6_drift_blocks_before_stop_and_retains_failure(self):
        plan = json.loads(self.drill("plan").stdout); self.rdisc.write_text("#!/bin/sh\nexit 1\n"); self.rdisc.chmod(0o700)
        run_dir = self.root / "rdisc-drift"; observer_called = self.root / "observer-called"
        args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
        result = subprocess.run(args, env=os.environ | {"OBS_JSON": str(self.obs_json), "OBSERVER_CALLED": str(observer_called)}, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0); self.assertTrue((run_dir / "failure.json").exists()); self.assertFalse((run_dir / "journal.jsonl").read_text()); self.assertFalse(observer_called.exists())

    def test_rdnss_order_and_cached_nonce_drift_block_before_stop(self):
        plan = json.loads(self.drill("plan").stdout)
        for mode in ("rdnss", "order", "stale"):
            run_dir = self.root / f"fresh-{mode}"
            args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client,
                self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
            extra = {"STALE_NONCE": "1"} if mode == "stale" else {"FRESH_DRIFT": mode}
            result = subprocess.run(args, env=os.environ | {"OBS_JSON": str(self.obs_json),
                "POST_DRIFT": "0", "RESTORED": str(self.root / "restored")} | extra,
                text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, mode)
            self.assertTrue((run_dir / "failure.json").exists(), mode)
            self.assertFalse((run_dir / "journal.jsonl").read_text(), mode)

    def test_observer_rootless_strict_ssh_full_allowlist_and_gateway_rdnss(self):
        bindir = self.root / "bin"; bindir.mkdir(); log = self.root / "log"; containers = self.root / "containers.json"; containers.write_text(json.dumps(raw_containers()))
        executable(bindir / "sudo", '[ "$1" = -n ] || exit 90; shift; [ "$SUDO_DENY" = 1 ] && exit 1; exec "$@"\n')
        executable(bindir / "timeout", 'shift; "$@"\n')
        executable(bindir / "ip", r'''case "$*" in
 "netns list") echo p3-dhcp-proof;;
 "-n p3-dhcp-proof -d link show dev p3d1234") echo macvlan;;
 "-n p3-dhcp-proof -o link show") printf '1: lo: x\n2: p3d1234@if3: x\n';;
 "-j -n p3-dhcp-proof -6 route show default") gateway=fe80::1; [ "$RA_MODE" = route ] && gateway=fe80::2; printf '[{"dst":"default","gateway":"%s","dev":"p3d1234","protocol":"ra","expires":1200}]\n' "$gateway";;
 "-j -n p3-dhcp-proof -6 address show dev p3d1234 scope link") if [ "$RA_MODE" = missing-link-local ];then echo '[]';else echo '[{"addr_info":[{"family":"inet6","local":"fe80::1234","prefixlen":64,"scope":"link"}]}]';fi;;
 netns\ exec\ p3-dhcp-proof\ cat\ /etc/resolv.conf) if [ "$RA_MODE" = resolver-order ];then printf 'nameserver 192.168.10.210\nnameserver 2001:db8:10::53\nnameserver 192.168.10.230\noptions timeout:2 attempts:1\n';elif [ "$RA_MODE" = resolver-extra ];then printf 'nameserver 2001:db8:10::53\nnameserver 192.168.10.210\nnameserver 192.168.10.230\noptions timeout:2 attempts:1\nsearch invalid.example\n';else printf 'nameserver 2001:db8:10::53\nnameserver 192.168.10.210\nnameserver 192.168.10.230\noptions timeout:2 attempts:1\n';fi;;
 netns\ exec\ p3-dhcp-proof\ *dig*) case "$*" in *".invalid A"*) echo 'status: NXDOMAIN, ANSWER: 0';; *doubleclick.net*) if [ "$FILTER_NXDOMAIN" = 1 ];then echo 'status: NXDOMAIN, ANSWER: 0';else echo 'status: NOERROR, ANSWER: 1 0.0.0.0';fi;; *homelab.pastelariadev.com*AAAA*) echo 'status: NOERROR, ANSWER: 0';; *homelab.pastelariadev.com*) echo 'status: NOERROR, ANSWER: 1 192.168.10.210';; *AAAA*) echo 'status: NOERROR, ANSWER: 1 2001:db8::1';; *) echo 'status: NOERROR, ANSWER: 1 93.184.216.34';; esac;;
 netns\ exec\ p3-dhcp-proof\ *) shift 3; "$@";; esac
''')
        executable(bindir / "ssh", '''echo "$*" >>"$LOG"; case "$*" in
 *"docker info"*) exit 0;;
 *"docker ps"*) if [ "$IGNORE_NO_TRUNC" = 1 ] || ! printf '%s' "$*"|grep -Fq 'docker ps --no-trunc -aq --filter label=com.docker.compose.project=networking';then jq -r '.[].Id[0:12]' "$CONTAINERS";else jq -r '.[].Id' "$CONTAINERS";fi; [ "$EXTRA_PROJECT" = 1 ] && printf '%064d\n' 9;;
 *"docker inspect"*) cat "$CONTAINERS";; esac
''')
        env = os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}", "LOG": str(log), "CONTAINERS": str(containers), "RA_MODE": "", "SUDO_DENY": "0", "EXTRA_PROJECT": "0", "FILTER_NXDOMAIN": "0", "IGNORE_NO_TRUNC": "0"}
        args = [OBSERVE, "p3-dhcp-proof", "p3d1234", "192.168.10.210", "5000", self.known, self.rdisc, CLIENT, CALLBACK]
        good = subprocess.run(args, env=env, text=True, capture_output=True); self.assertEqual(good.returncode, 0, good.stderr)
        filtered_nxdomain = subprocess.run(args, env=env | {"FILTER_NXDOMAIN": "1"}, text=True, capture_output=True); self.assertEqual(filtered_nxdomain.returncode, 0, filtered_nxdomain.stderr)
        value = json.loads(good.stdout); self.assertEqual([x["name"] for x in value["containers"]], sorted(NAMES)); self.assertEqual(value["ipv6"], observation(raw_containers())["ipv6"])
        self.assertEqual(value["resolvers"], observation(raw_containers())["resolvers"]); self.assertEqual(value["probe_contract"], observation(raw_containers())["probe_contract"])
        self.assertEqual(set(value["probe_evidence"]), {"classifications_sha256", "nonce_sha256", "qnames_sha256", "results_sha256"})
        for digest in value["probe_evidence"].values(): self.assertRegex(digest, r"^[0-9a-f]{64}$")
        ssh_log = log.read_text(); self.assertIn("StrictHostKeyChecking=yes", ssh_log); self.assertIn(f"UserKnownHostsFile={self.known}", ssh_log); self.assertNotIn("sudo docker", ssh_log)
        self.assertIn("docker ps --no-trunc -aq --filter label=com.docker.compose.project=networking", ssh_log)
        short_ids = subprocess.run(args, env=env | {"IGNORE_NO_TRUNC": "1"}, text=True, capture_output=True)
        self.assertNotEqual(short_ids.returncode, 0); self.assertNotIn("docker inspect", log.read_text().split("docker ps")[-1])
        for mode in ("route", "resolver-order", "resolver-extra", "missing-link-local"):
            bad = subprocess.run(args, env=env | {"RA_MODE": mode}, text=True, capture_output=True); self.assertNotEqual(bad.returncode, 0, mode)
        denied = subprocess.run(args, env=env | {"SUDO_DENY": "1"}, text=True, capture_output=True); self.assertNotEqual(denied.returncode, 0)
        extra = subprocess.run(args, env=env | {"EXTRA_PROJECT": "1"}, text=True, capture_output=True); self.assertNotEqual(extra.returncode, 0)

    def test_drift_fields_and_exact_allowlist_change_inventory(self):
        base = observation(raw_containers())
        for field, value in (("image_ref", "changed"), ("restart_count", 1), ("mounts", []), ("networks", []), ("health", "unhealthy")):
            changed = json.loads(json.dumps(base)); changed["containers"][0][field] = value
            self.assertNotEqual(json.dumps(base, sort_keys=True), json.dumps(changed, sort_keys=True))
        self.assertEqual({x["name"] for x in base["containers"]}, set(NAMES)); self.assertEqual(next(x for x in base["containers"] if x["name"] == "swag-init")["state"], "exited")

    def test_source_has_bounded_three_attempt_recovery_and_no_remote_sudo(self):
        source = DRILL.read_text(); self.assertIn("for attempt in 1 2 3", source); self.assertIn("mkdir -m 0700", source); self.assertIn("mv -n", source)
        self.assertNotIn('"sudo docker', source); self.assertIn("trap recover EXIT INT TERM", source); self.assertIn("rm -f", source)
        client = CLIENT.read_text(); self.assertNotIn("trap 'rm -f \"$capture\"' RETURN", client); self.assertIn('[ -n "$capture" ]&&rm -f "$capture"', client); self.assertIn('[ -n "$tmp" ]&&rm -f "$tmp"', client)
        self.assertNotIn('-6 address add', client); self.assertNotIn(' nodad', client)
        self.assertIn('wait_for_kernel_link_local "$namespace" "$probe"', client)
        self.assertLess(client.index('wait_for_kernel_link_local "$namespace" "$probe"'), client.index('"$rdisc6" -1 "$probe"'))

    def test_kernel_link_local_wait_accepts_delay_and_rejects_timeout_or_multiple(self):
        source = CLIENT.read_text().splitlines()
        start = next(index for index, line in enumerate(source) if line.startswith("wait_for_kernel_link_local()"))
        end = next(index for index in range(start + 1, len(source)) if source[index] == "}")
        function = "\n".join(source[start:end + 1])
        fake_ip = self.root / "ip"; counter = self.root / "link-local-count"
        executable(fake_ip, r'''count=0; [ -e "$LL_COUNTER" ] && count=$(cat "$LL_COUNTER"); count=$((count+1)); printf '%s\n' "$count" >"$LL_COUNTER"
case "$LL_MODE" in
 delayed) [ "$count" -lt 2 ] && echo '[]' || echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll"}]}]' ;;
 absent-protocol) echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link"}]}]' ;;
 tentative) [ "$count" -lt 2 ] && echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll","tentative":true}]}]' || echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll"}]}]' ;;
 timeout) echo '[]' ;;
 multiple) echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll"},{"family":"inet6","local":"fe80::2","scope":"link","protocol":"kernel_ll"}]}]' ;;
 dadfailed) echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll","dadfailed":true}]}]' ;;
 mixed) echo '[{"addr_info":[{"family":"inet6","local":"fe80::1","scope":"link","protocol":"kernel_ll"},{"family":"inet6","local":"fe80::2","scope":"link","protocol":"static"}]}]' ;;
esac
''')
        command = f"{function}\nwait_for_kernel_link_local proof p3d1234"
        base = os.environ | {"PATH": f"{self.root}:{os.environ['PATH']}", "LL_COUNTER": str(counter),
            "P3_LINK_LOCAL_ATTEMPTS": "3", "P3_LINK_LOCAL_DELAY": "0"}
        delayed = subprocess.run(["bash", "-c", command], env=base | {"LL_MODE": "delayed"}, text=True, capture_output=True)
        self.assertEqual(delayed.returncode, 0, delayed.stderr); self.assertEqual(counter.read_text(), "2\n")
        counter.unlink(); absent = subprocess.run(["bash", "-c", command], env=base | {"LL_MODE": "absent-protocol"}, text=True, capture_output=True)
        self.assertEqual(absent.returncode, 0, absent.stderr)
        counter.unlink(); tentative = subprocess.run(["bash", "-c", command], env=base | {"LL_MODE": "tentative"}, text=True, capture_output=True)
        self.assertEqual(tentative.returncode, 0, tentative.stderr); self.assertEqual(counter.read_text(), "2\n")
        for mode in ("timeout", "multiple", "dadfailed", "mixed"):
            counter.unlink(missing_ok=True)
            result = subprocess.run(["bash", "-c", command], env=base | {"LL_MODE": mode}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, mode)
        for attempts, delay in (("0", "0"), ("31", "0"), ("bogus", "0"), ("3", "0.251"), ("3", "9"), ("3", "bogus")):
            counter.unlink(missing_ok=True)
            result = subprocess.run(["bash", "-c", command], env=base | {"LL_MODE": "delayed",
                "P3_LINK_LOCAL_ATTEMPTS": attempts, "P3_LINK_LOCAL_DELAY": delay}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, (attempts, delay))

    def test_recovery_succeeds_on_attempts_one_two_three_or_records_exhaustion(self):
        bindir = self.root / "lifecycle-bin"; bindir.mkdir(); log = self.root / "lifecycle.log"; counter = self.root / "counter"
        executable(bindir / "timeout", 'shift; exec "$@"\n')
        executable(bindir / "sudo", '[ "$1" = -n ] || exit 90; shift; case "$*" in *getent*) [ "$PROBE_FAIL" = 1 ] && exit 1;; esac; exec "$@"\n')
        executable(bindir / "ip", r'''case "$*" in
 netns\ exec\ *\ getent\ *) exit 0;;
 netns\ exec\ *\ dig\ *) if [ "$OUTAGE_FAIL" = 1 ] && [ ! -e "$RESTORED" ];then exit 1;fi; if [ "$OUTAGE_TIMEOUT" = 1 ] && [ ! -e "$RESTORED" ];then sleep 0.02;fi; case "$*" in *".invalid A"*) echo 'status: NXDOMAIN, ANSWER: 0';; *doubleclick.net*) echo 'status: NOERROR, ANSWER: 1 0.0.0.0';; *homelab.pastelariadev.com*AAAA*) echo 'status: NOERROR, ANSWER: 0';; *homelab.pastelariadev.com*) echo 'status: NOERROR, ANSWER: 1 192.168.10.210';; *AAAA*) echo 'status: NOERROR, ANSWER: 1 2001:db8::1';; *) echo 'status: NOERROR, ANSWER: 1 93.184.216.34';; esac;; esac
''')
        executable(bindir / "ssh", '''for cmd do :;done; echo "$cmd" >>"$LOG"
case "$cmd" in
 *"docker stop"*) exit 0;;
 *"docker inspect -f '{{.State.Status}}'"*) printf 'exited\nexited\n';;
 *"docker start aaaa"*) n=0; [ -f "$COUNTER" ] && n=$(cat "$COUNTER"); n=$((n+1)); echo "$n" >"$COUNTER"; [ "$n" -le "$START_FAILS" ] && exit 1; exit 0;;
 *"State.Health"*) n=0; [ -f "$HEALTH_COUNTER" ] && n=$(cat "$HEALTH_COUNTER"); n=$((n+1)); echo "$n" >"$HEALTH_COUNTER"; [ "$n" -le "$HEALTH_DELAYS" ] && echo starting || echo healthy;;
 *"docker start bbbb"*) touch "$RESTORED"; exit 0;;
 *"docker inspect bbbb"*) printf '[{"Id":"%s","NetworkSettings":{"Networks":{"homelab-net":{"IPAddress":"172.30.0.2"}}}}]\n' "$(printf 'b%.0s' {1..64})";;
 *"9618/metrics"*) n=0; [ -f "$METRICS_COUNTER" ] && n=$(cat "$METRICS_COUNTER"); n=$((n+1)); echo "$n" >"$METRICS_COUNTER"; [ "$n" -le "$METRIC_DELAYS" ] && exit 1; printf '# TYPE adguard_queries counter\n# TYPE adguard_queries_blocked counter\n# TYPE adguard_avg_processing_time_seconds gauge\n';;
 *curl*) exit 0;; esac
''')
        env = os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}", "OBS_JSON": str(self.obs_json), "LOG": str(log), "COUNTER": str(counter), "RESTORED": str(self.root / "restored"), "POST_DRIFT": "0", "PROBE_FAIL": "1", "OUTAGE_FAIL": "0", "OUTAGE_TIMEOUT": "0", "HEALTH_COUNTER": str(self.root / "health-counter"), "METRICS_COUNTER": str(self.root / "metrics-counter"), "HEALTH_DELAYS": "0", "METRIC_DELAYS": "0"}
        for failures, expected_attempts, exhausted in ((0, 1, False), (1, 2, False), (2, 3, False), (3, 3, True)):
            counter.unlink(missing_ok=True); pathlib.Path(env["RESTORED"]).unlink(missing_ok=True); log.write_text(""); run_dir = self.root / f"run-{failures}"
            plan = json.loads(self.drill("plan", env=env).stdout)
            args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
            result = subprocess.run(args, env=env | {"START_FAILS": str(failures)}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertEqual(result.stdout, "")
            journal = (run_dir / "journal.jsonl").read_text(); self.assertEqual(journal.count('"event":"recovery-attempt"'), expected_attempts)
            self.assertTrue((run_dir / "failure.json").exists()); self.assertEqual("docker start " + "b" * 64 in log.read_text(), not exhausted)
            self.assertNotIn("sudo docker", log.read_text())

    def test_success_journals_all_phases_and_postrestore_drift_fails_closed(self):
        # Reuse the lifecycle builder, then independently execute with a successful probe.
        self.test_recovery_succeeds_on_attempts_one_two_three_or_records_exhaustion()
        bindir = self.root / "lifecycle-bin"; env = os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}", "OBS_JSON": str(self.obs_json), "LOG": str(self.root / "lifecycle.log"), "COUNTER": str(self.root / "counter"), "RESTORED": str(self.root / "restored"), "START_FAILS": "0", "PROBE_FAIL": "0", "POST_DRIFT": "0", "HEALTH_COUNTER": str(self.root / "health-counter"), "METRICS_COUNTER": str(self.root / "metrics-counter"), "HEALTH_DELAYS": "2", "METRIC_DELAYS": "2"}
        for drift, expected in (("0", 0), ("1", 1)):
            for key in ("RESTORED", "COUNTER", "HEALTH_COUNTER", "METRICS_COUNTER"): pathlib.Path(env[key]).unlink(missing_ok=True)
            run_dir = self.root / f"success-{drift}"; plan = json.loads(self.drill("plan", env=env).stdout)
            args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
            result = subprocess.run(args, env=env | {"POST_DRIFT": drift}, text=True, capture_output=True)
            self.assertEqual(result.returncode, expected, result.stderr); journal = (run_dir / "journal.jsonl").read_text()
            for phase in ("stop-exporter", "stop-adguard", "stopped-gate", "failover-probe", "secondary-matrix", "recovery-attempt"):
                self.assertIn(f'"event":"{phase}"', journal)
            artifact_path = run_dir / ("result.json" if expected == 0 else "failure.json"); self.assertTrue(artifact_path.exists())
            if expected == 0:
                artifact = json.loads(artifact_path.read_text())
                self.assertRegex(artifact["outage_results_sha256"], r"^[0-9a-f]{64}$")
                self.assertEqual(artifact["outage_results_sha256"], artifact["partial_outage_results_sha256"])

    def test_outage_deadline_failure_preserves_original_rc_after_successful_recovery_checks(self):
        self.test_recovery_succeeds_on_attempts_one_two_three_or_records_exhaustion()
        bindir = self.root / "lifecycle-bin"
        restored = self.root / "restored"; restored.unlink(missing_ok=True)
        bounded = observation(raw_containers()); bounded["failover_bound_ms"] = 1
        self.obs_json.write_text(json.dumps(bounded))
        env = os.environ | {
            "PATH": f"{bindir}:{os.environ['PATH']}", "OBS_JSON": str(self.obs_json),
            "LOG": str(self.root / "lifecycle.log"), "COUNTER": str(self.root / "counter"),
            "RESTORED": str(restored), "START_FAILS": "0", "PROBE_FAIL": "0",
            "OUTAGE_FAIL": "0", "OUTAGE_TIMEOUT": "1", "POST_DRIFT": "0",
            "HEALTH_COUNTER": str(self.root / "health-counter"),
            "METRICS_COUNTER": str(self.root / "metrics-counter"),
            "HEALTH_DELAYS": "0", "METRIC_DELAYS": "0",
        }
        for key in ("COUNTER", "HEALTH_COUNTER", "METRICS_COUNTER"):
            pathlib.Path(env[key]).unlink(missing_ok=True)
        run_dir = self.root / "outage-partial-failure"
        plan = json.loads(self.drill("plan", env=env).stdout)
        args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client,
            self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
        result = subprocess.run(args, env=env, text=True, capture_output=True)

        self.assertNotEqual(result.returncode, 0)
        artifact = json.loads((run_dir / "failure.json").read_text())
        journal = (run_dir / "journal.jsonl").read_text()
        records = [json.loads(line) for line in journal.splitlines()]
        failures = []
        if artifact.get("original_failure_rc", 0) <= 0: failures.append("original_failure_rc")
        if artifact.get("recovery_failed") is not False: failures.append("recovery_failed")
        if artifact.get("actual_elapsed_ms") is None: failures.append("actual_elapsed_ms")
        if artifact.get("outage_results_sha256") is not None:
            failures.append("full-outage-hash-on-partial-evidence")
        if not re.fullmatch(r"[0-9a-f]{64}", artifact.get("partial_outage_results_sha256") or ""):
            failures.append("partial-outage-results-hash")
        if not re.fullmatch(r"[0-9a-f]{64}", artifact.get("postrestore_results_sha256") or ""):
            failures.append("postrestore-results-hash")
        if not any(record.get("event") == "postrestore-checks" and
                   record.get("status") == "passed" for record in records):
            failures.append("postrestore-checks-passed")
        source = DRILL.read_text()
        if "frozen_outage_results_sha256" not in source:
            failures.append("frozen-outage-hash")
        else:
            freeze = source.index("frozen_outage_results_sha256")
            recovery = source.index("recover() {")
            postrestore = source.index("postrestore_operational")
            if not freeze < recovery < postrestore: failures.append("freeze-order")
            if re.search(r"frozen_outage_results_sha256\s*=", source[recovery:]):
                failures.append("outage-hash-mutated-during-recovery")
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
