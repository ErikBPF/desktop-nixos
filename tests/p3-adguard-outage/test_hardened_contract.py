import hashlib
import json
import os
import pathlib
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
        "containers": sorted(projected, key=lambda x: x["name"]), "dhcp_dns": ["192.168.10.210", "192.168.10.230"],
        "failover_bound_ms": 5000, "ipv6": {"default_routes": [], "rdnss": [], "ra_probe": "bounded-no-ra"},
        "remote": {"ip": "192.168.10.210", "recovery_by_ip": True}, "version": 3}


class HardenedContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name); self.known = self.root / "known_hosts"; self.known.write_text("[192.168.10.210]:2222 key\n");self.known.chmod(0o400)
        self.rdisc = self.root / "rdisc6"; executable(self.rdisc, "[ \"$RA_MODE\" = response ] && { echo 'Router advertisement RDNSS'; exit 0; }; [ \"$RA_MODE\" = toolfail ] && exit 1; [ \"$RA_MODE\" = timeout ] && exit 124; echo 'No response'; exit 2\n")
        self.obs_json = self.root / "observation.json"; self.obs_json.write_text(json.dumps(observation(raw_containers())))
        self.fake_observer = self.root / "observer"; executable(self.fake_observer, '''[ -n "${OBSERVER_CALLED:-}" ] && touch "$OBSERVER_CALLED"
if [ "$POST_DRIFT" = 1 ] && [ -e "$RESTORED" ];then jq '.containers |= map(if .name=="swag" then .image_ref="drift" else . end)' "$OBS_JSON";else cat "$OBS_JSON";fi
''')
        self.fake_client = self.root / "client"; executable(self.fake_client, "exit 0\n")
        self.fake_callback = self.root / "callback"; executable(self.fake_callback, "exit 0\n")

    def drill(self, *tail, env=None):
        args = [DRILL, *tail, self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback]
        return subprocess.run(args, text=True, capture_output=True, env=(os.environ | {"OBS_JSON": str(self.obs_json), "POST_DRIFT": "0", "RESTORED": str(self.root / "restored")} | (env or {})))

    def test_manifest_v2_binds_inventory_and_all_implementations(self):
        result = self.drill("plan"); self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout); manifest = value["manifest"]
        self.assertEqual(manifest["version"], 2); self.assertEqual(set(manifest["bindings"]), {"client_sha256", "observer_sha256", "drill_sha256", "callback_sha256", "known_hosts_sha256", "rdisc6_sha256"})
        canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":")); self.assertEqual(value["manifest_sha256"], hashlib.sha256(canonical.encode()).hexdigest())
        old = value["manifest_sha256"]; self.known.chmod(0o600);self.known.write_text("changed\n");self.known.chmod(0o400); self.assertNotEqual(old, json.loads(self.drill("plan").stdout)["manifest_sha256"])
        self.known.chmod(0o600); self.assertNotEqual(self.drill("plan").returncode, 0); self.known.chmod(0o400)
        target = self.root / "known-target"; self.known.rename(target); self.known.symlink_to(target); self.assertNotEqual(self.drill("plan").returncode, 0)

    def test_rdisc6_drift_blocks_before_stop_and_retains_failure(self):
        plan = json.loads(self.drill("plan").stdout); self.rdisc.write_text("#!/bin/sh\nexit 1\n"); self.rdisc.chmod(0o700)
        run_dir = self.root / "rdisc-drift"; observer_called = self.root / "observer-called"
        args = [DRILL, "execute", self.obs_json, self.known, self.rdisc, self.fake_client, self.fake_observer, self.fake_callback, run_dir, plan["manifest_sha256"]]
        result = subprocess.run(args, env=os.environ | {"OBS_JSON": str(self.obs_json), "OBSERVER_CALLED": str(observer_called)}, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0); self.assertTrue((run_dir / "failure.json").exists()); self.assertFalse((run_dir / "journal.jsonl").read_text()); self.assertFalse(observer_called.exists())

    def test_observer_rootless_strict_ssh_full_allowlist_and_no_ra(self):
        bindir = self.root / "bin"; bindir.mkdir(); log = self.root / "log"; containers = self.root / "containers.json"; containers.write_text(json.dumps(raw_containers()))
        executable(bindir / "sudo", '[ "$1" = -n ] || exit 90; shift; [ "$SUDO_DENY" = 1 ] && exit 1; exec "$@"\n')
        executable(bindir / "timeout", 'shift; "$@"\n')
        executable(bindir / "ip", r'''case "$*" in
 "netns list") echo p3-dhcp-proof;;
 "-n p3-dhcp-proof -d link show dev p3d1234") echo macvlan;;
 "-n p3-dhcp-proof -o link show") printf '1: lo: x\n2: p3d1234@if3: x\n';;
 "-n p3-dhcp-proof -6 route show default") [ "$RA_MODE" = route ] && echo 'default via fe80::1';;
 "-j -n p3-dhcp-proof -6 address show dev p3d1234 scope link") if [ "$RA_MODE" = missing-link-local ];then echo '[]';else echo '[{"addr_info":[{"family":"inet6","local":"fe80::1234","prefixlen":64,"scope":"link"}]}]';fi;;
 netns\ exec\ p3-dhcp-proof\ awk\ *) if [ "$RA_MODE" = resolver ];then printf '192.168.10.210\n192.168.10.230\nfe80::1\n';else printf '192.168.10.210\n192.168.10.230\n';fi;;
 netns\ exec\ p3-dhcp-proof\ *) shift 3; if [ "$RA_MODE" = response ];then echo 'Router advertisement RDNSS';exit 0;else "$@";fi;; esac
''')
        executable(bindir / "ssh", '''echo "$*" >>"$LOG"; case "$*" in
 *"docker info"*) exit 0;;
 *"docker ps -aq"*) jq -r '.[].Id' "$CONTAINERS"; [ "$EXTRA_PROJECT" = 1 ] && printf '%064d\n' 9;;
 *"docker inspect"*) cat "$CONTAINERS";; esac
''')
        env = os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}", "LOG": str(log), "CONTAINERS": str(containers), "RA_MODE": "", "SUDO_DENY": "0", "EXTRA_PROJECT": "0"}
        args = [OBSERVE, "p3-dhcp-proof", "p3d1234", "192.168.10.210", "5000", self.known, self.rdisc, CLIENT, CALLBACK]
        good = subprocess.run(args, env=env, text=True, capture_output=True); self.assertEqual(good.returncode, 0, good.stderr)
        value = json.loads(good.stdout); self.assertEqual([x["name"] for x in value["containers"]], sorted(NAMES)); self.assertEqual(value["ipv6"]["ra_probe"], "bounded-no-ra")
        ssh_log = log.read_text(); self.assertIn("StrictHostKeyChecking=yes", ssh_log); self.assertIn(f"UserKnownHostsFile={self.known}", ssh_log); self.assertNotIn("sudo docker", ssh_log)
        for mode in ("route", "resolver", "response", "toolfail", "timeout", "missing-link-local"):
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
        self.assertIn('-6 address add "$link_local/64" dev "$probe" nodad', client); self.assertIn('-6 address show dev "$probe" scope link', client)

    def test_recovery_succeeds_on_attempts_one_two_three_or_records_exhaustion(self):
        bindir = self.root / "lifecycle-bin"; bindir.mkdir(); log = self.root / "lifecycle.log"; counter = self.root / "counter"
        executable(bindir / "timeout", 'shift; exec "$@"\n')
        executable(bindir / "sudo", '[ "$1" = -n ] || exit 90; shift; case "$*" in *getent*) [ "$PROBE_FAIL" = 1 ] && exit 1;; esac; exec "$@"\n')
        executable(bindir / "ip", r'''case "$*" in
 netns\ exec\ *\ getent\ *) exit 0;;
 netns\ exec\ *\ dig\ *) case "$*" in *p3-nonexistent.invalid*) echo 'status: NXDOMAIN, ANSWER: 0';; *doubleclick.net*) echo 'status: NOERROR, ANSWER: 1 0.0.0.0';; *homelab.pastelariadev.com*AAAA*) echo 'status: NOERROR, ANSWER: 0';; *homelab.pastelariadev.com*) echo 'status: NOERROR, ANSWER: 1 192.168.10.210';; *AAAA*) echo 'status: NOERROR, ANSWER: 1 2001:db8::1';; *) echo 'status: NOERROR, ANSWER: 1 93.184.216.34';; esac;; esac
''')
        executable(bindir / "ssh", '''for cmd do :;done; echo "$cmd" >>"$LOG"
case "$cmd" in
 *"docker stop"*) exit 0;;
 *"docker inspect -f '{{.State.Status}}'"*) printf 'exited\nexited\n';;
 *"docker start aaaa"*) n=0; [ -f "$COUNTER" ] && n=$(cat "$COUNTER"); n=$((n+1)); echo "$n" >"$COUNTER"; [ "$n" -le "$START_FAILS" ] && exit 1; exit 0;;
 *"State.Health"*) n=0; [ -f "$HEALTH_COUNTER" ] && n=$(cat "$HEALTH_COUNTER"); n=$((n+1)); echo "$n" >"$HEALTH_COUNTER"; [ "$n" -le "$HEALTH_DELAYS" ] && echo starting || echo healthy;;
 *"docker start bbbb"*) touch "$RESTORED"; exit 0;;
 *"9618/metrics"*) n=0; [ -f "$METRICS_COUNTER" ] && n=$(cat "$METRICS_COUNTER"); n=$((n+1)); echo "$n" >"$METRICS_COUNTER"; [ "$n" -le "$METRIC_DELAYS" ] && exit 1; printf '# TYPE adguard_queries counter\n# TYPE adguard_queries_blocked counter\n# TYPE adguard_avg_processing_time_seconds gauge\n';;
 *curl*) exit 0;; esac
''')
        env = os.environ | {"PATH": f"{bindir}:{os.environ['PATH']}", "OBS_JSON": str(self.obs_json), "LOG": str(log), "COUNTER": str(counter), "RESTORED": str(self.root / "restored"), "POST_DRIFT": "0", "PROBE_FAIL": "1", "HEALTH_COUNTER": str(self.root / "health-counter"), "METRICS_COUNTER": str(self.root / "metrics-counter"), "HEALTH_DELAYS": "0", "METRIC_DELAYS": "0"}
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
            self.assertTrue((run_dir / ("result.json" if expected == 0 else "failure.json")).exists())


if __name__ == "__main__":
    unittest.main()
