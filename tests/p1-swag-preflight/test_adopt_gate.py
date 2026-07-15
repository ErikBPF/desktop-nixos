import pathlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
ADOPT = ROOT / "modules/hosts/discovery/_stateful-swag-adopt.sh"
INVENTORY = pathlib.Path(__file__).parent / "fixtures/inventory.json"
RAW = pathlib.Path(__file__).parent / "fixtures/raw-observations.json"
PLANNER = ROOT / "modules/hosts/discovery/_stateful-swag-preflight.py"


def authorization_fixture():
    spec = importlib.util.spec_from_file_location("swag_preflight_for_adopt", PLANNER)
    planner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(planner)
    inventory = json.loads(INVENTORY.read_text())
    return planner.envelope(planner.plan(inventory))


class SwagAdoptGateTest(unittest.TestCase):
    def test_both_containers_are_bound_and_rollback_never_evals_ledger_text(self):
        source = ADOPT.read_text()
        self.assertIn("swag-init", source)
        self.assertIn("capture-runtime", source)
        self.assertIn('docker stop --time 30 "$swag_id"', source)
        self.assertIn("rollback)", source)
        self.assertNotIn("eval ", source)
        self.assertNotIn("bash -c", source)

    def test_rollback_requires_exact_contract_ledger_archive_and_snapshot(self):
        source = ADOPT.read_text()
        for required in (
            "assert_workflow_contract", '.rollback_command == $rollback',
            '[ "$checksum_path" = "$archive" ]', 'btrfs subvolume show "$snapshot"',
            '.physical_source ==', '.copy_destination == $restore_target',
        ):
            self.assertIn(required, source)

    def test_rollback_rejects_invalid_hash_before_runtime_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            log = root / "runtime.log"
            for name, body in {
                "id": "#!/bin/sh\necho 0\n",
                "docker": f"#!/bin/sh\necho docker >>'{log}'\n",
                "docker-compose": f"#!/bin/sh\necho compose >>'{log}'\n",
            }.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{root}:{pathlib.Path.home() / '.nix-profile/bin'}:/run/current-system/sw/bin:/usr/bin:/bin"
            result = subprocess.run(["bash", str(ADOPT), "rollback", "--manifest-sha", "short"], check=False, capture_output=True, text=True, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest SHA-256 invalid", result.stderr)
            self.assertFalse(log.exists())

    def test_rollback_tamper_table_never_reaches_compose(self):
        cases = ("rollback-command", "physical-source", "checksum-target", "non-subvolume")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                repository = root / "servarr"
                discovery = repository / "machines/discovery"
                evidence = root / "evidence"
                snapshot = root / "snapshot"
                archive = evidence / "swag-config.tar.zst"
                restore = evidence / "restore-only-after-approval"
                vault_env = root / "networking.env"
                for path in (discovery / "networking.yml", discovery / ".env", vault_env):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("fixture")
                evidence.mkdir(parents=True)
                snapshot.mkdir()
                archive.write_text("retained archive")
                authorization = authorization_fixture()
                (evidence / "authorization.json").write_text(json.dumps(authorization))
                (evidence / "approved-inventory.json").write_text(INVENTORY.read_text())
                checksum = subprocess.check_output(["sha256sum", str(archive)], text=True).split()[0]
                checksum_target = "/wrong/archive" if case == "checksum-target" else str(archive)
                (evidence / "swag-config.tar.zst.sha256").write_text(f"{checksum}  {checksum_target}\n")
                physical_source = "/wrong/source" if case == "physical-source" else str(discovery / "config/swag")
                rollback_command = "tampered" if case == "rollback-command" else "discovery-stateful-swag-adopt rollback --manifest-sha APPROVED_MANIFEST_SHA256"
                ledger = {
                    "archive_id": str(archive), "compose_owner": str(discovery), "compose_project": "networking",
                    "container": "swag", "copy_destination": str(restore), "expected_downtime": "up to 2 minutes",
                    "git_commit": "5" * 40, "image_digest": "sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d",
                    "image_tag": "lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d",
                    "mount_target": "/config", "ownership": "1000:1000", "physical_source": physical_source,
                    "physical_volume": physical_source, "recorded_at": "2026-07-15T00:00:00Z",
                    "rollback_command": rollback_command, "size_bytes": 1, "snapshot_id": str(snapshot),
                    "snapshot_source": "/home", "version": 1, "volume_type": "bind",
                }
                (evidence / "ledger.json").write_text(json.dumps(ledger))
                source = ADOPT.read_text()
                source = source.replace("readonly repository=/home/erik/servarr", f"readonly repository={repository}")
                source = source.replace("readonly vault_env=/run/vault-agent/networking.env", f"readonly vault_env={vault_env}")
                source = source.replace("readonly evidence=/var/lib/stateful-stack-migrations/p1-swag", f"readonly evidence={evidence}")
                source = source.replace("readonly snapshot=/home/.snapshots/stateful-stack-p1-swag", f"readonly snapshot={snapshot}")
                script = root / "adopt.sh"
                script.write_text(source)
                compose_log = root / "compose.log"
                for name, body in {
                    "id": "#!/bin/sh\necho 0\n",
                    "discovery-stateful-swag-preflight": "#!/bin/sh\nexit 0\n",
                    "docker-compose": f"#!/bin/sh\necho compose >>'{compose_log}'\n",
                    "btrfs": "#!/bin/sh\nexit 1\n",
                }.items():
                    path = root / name
                    path.write_text(body)
                    path.chmod(0o755)
                env = os.environ.copy()
                env["PATH"] = f"{root}:{pathlib.Path.home() / '.nix-profile/bin'}:/run/current-system/sw/bin:/usr/bin:/bin"
                result = subprocess.run(
                    ["bash", str(script), "rollback", "--manifest-sha", authorization["manifest_sha256"]],
                    check=False, capture_output=True, text=True, env=env,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(compose_log.exists(), msg=f"case {case} reached Compose")

    def test_drift_failure_runs_no_runtime_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            log = root / "mutations"
            authorization = root / "authorization.json"
            authorization.write_text(json.dumps(authorization_fixture()))
            approved_sha = json.loads(authorization.read_text())["manifest_sha256"]
            commands = {
                "id": "#!/bin/sh\necho 0\n",
                "discovery-stateful-swag-inventory": "#!/bin/sh\necho '{}'\n",
                "discovery-stateful-swag-preflight": "#!/bin/sh\nexit 1\n",
            }
            for name in ("docker", "docker-compose", "discovery-stateful-stack-ops", "install", "mkdir"):
                commands[name] = f"#!/bin/sh\necho {name} >>'{log}'\nexit 99\n"
            for name, body in commands.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{root}:{pathlib.Path.home() / '.nix-profile/bin'}:/run/current-system/sw/bin:/usr/bin:/bin"
            result = subprocess.run(
                ["bash", str(ADOPT), "execute", "--authorization", str(authorization), "--manifest-sha", approved_sha],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fresh inventory differs", result.stderr)
            self.assertFalse(log.exists())

    def test_successful_gate_orders_reinspection_before_captured_id_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repository = root / "servarr"
            discovery = repository / "machines/discovery"
            cert = discovery / "config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem"
            dns = discovery / "config/swag/dns-conf/cloudflare.ini"
            vault_env = root / "networking.env"
            evidence = root / "evidence"
            for path in (discovery / "networking.yml", discovery / ".env", cert, dns, vault_env):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            source = ADOPT.read_text()
            source = source.replace("readonly repository=/home/erik/servarr", f"readonly repository={repository}")
            source = source.replace("readonly vault_env=/run/vault-agent/networking.env", f"readonly vault_env={vault_env}")
            source = source.replace("readonly evidence=/var/lib/stateful-stack-migrations/p1-swag", f"readonly evidence={evidence}")
            source = source.replace("readonly snapshot=/home/.snapshots/stateful-stack-p1-swag", f"readonly snapshot={root / 'snapshot'}")
            source = source.replace("readonly cert=/home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem", f"readonly cert={cert}")
            source = source.replace("readonly dns_ini=/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini", f"readonly dns_ini={dns}")
            script = root / "adopt.sh"
            script.write_text(source)

            inventory = json.loads(INVENTORY.read_text())
            inventory["servarr"]["compose_file"] = str(discovery / "networking.yml")
            inventory_json = json.dumps(inventory, separators=(",", ":"))
            containers_json = json.dumps({"containers": inventory["containers"]}, separators=(",", ":"))
            raw_swag = json.loads(RAW.read_text())["container_inspects"][0]
            raw_swag["Config"]["Labels"]["com.docker.compose.project.working_dir"] = str(discovery)
            raw_swag["State"]["Health"] = {"Status": "healthy"}
            inspect_json = json.dumps([raw_swag], separators=(",", ":"))
            contract = {
                "execute_order": [
                    "capture-and-verify-fresh-inventory", "validate-no-clobber-evidence-set",
                    "persist-authorization-and-inventory", "create-ledger-and-baseline",
                    "reinspect-both-container-identities", "stop-captured-swag-id",
                    "snapshot-and-archive-stopped-state",
                    "recreate-swag-init-then-swag", "validate-health-state-certificate-and-routes",
                    "persist-result-and-rollback-evidence",
                ],
                "rollback": {"implementation": "fixed-compose-swag-recreate-v1", "pre_adoption_recovery": "start-exact-stopped-approved-swag-id-v1", "required_retained_evidence": ["approved_inventory", "authorization", "archive", "archive_sha256", "ledger", "snapshot"]},
                "version": 1,
            }
            authorization = root / "authorization.json"
            authorization.write_text(json.dumps({"manifest": {"workflow_contract": contract}, "manifest_sha256": "a" * 64}))
            log = root / "order.log"
            commands = {
                "id": "#!/bin/sh\necho 0\n",
                "discovery-stateful-swag-preflight": "#!/bin/sh\necho '{\"status\":\"binding-valid\"}'\necho preflight:$1 >>\"$ORDER_LOG\"\n",
                "discovery-stateful-swag-inventory": f"#!/bin/sh\necho inventory:$1 >>\"$ORDER_LOG\"\nif [ \"$1\" = capture-runtime ]; then echo '{containers_json}'; else echo '{inventory_json}'; fi\n",
                "discovery-stateful-stack-ops": "#!/bin/sh\necho ops:$1 >>\"$ORDER_LOG\"\n[ \"$1\" = archive ] && exit 88\nexit 0\n",
                "docker": f"#!/bin/sh\necho docker:$* >>\"$ORDER_LOG\"\nif [ \"$1\" = inspect ]; then echo '{inspect_json}'; exit 0; fi\nif [ \"$1\" = stop ]; then exit 0; fi\nexit 99\n",
                "openssl": "#!/bin/sh\ncase \"$*\" in *fingerprint*) echo 'sha256 Fingerprint=AA' ;; *startdate*) echo 'notBefore=Jul 1 00:00:00 2026 GMT' ;; *enddate*) echo 'notAfter=Oct 12 00:00:00 2026 GMT' ;; esac\n",
            }
            for name, body in commands.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = os.environ.copy()
            env["ORDER_LOG"] = str(log)
            env["PATH"] = f"{root}:{pathlib.Path.home() / '.nix-profile/bin'}:/run/current-system/sw/bin:/usr/bin:/bin"
            result = subprocess.run(
                ["bash", str(script), "execute", "--authorization", str(authorization), "--manifest-sha", "a" * 64],
                check=False, capture_output=True, text=True, env=env,
            )
            self.assertEqual(result.returncode, 1, msg=f"stderr={result.stderr}\nlog={log.read_text() if log.exists() else 'absent'}")
            self.assertIn("SWAG remains stopped and partial evidence is retained", result.stderr)
            events = log.read_text().splitlines()
            self.assertLess(events.index("inventory:capture"), events.index("preflight:verify"))
            stop = "docker:stop --time 30 " + "1" * 64
            self.assertLess(events.index("inventory:capture-runtime"), events.index(stop))
            self.assertLess(events.index(stop), events.index("ops:snapshot"))
            self.assertLess(events.index("ops:snapshot"), events.index("ops:archive"))

    def test_snapshot_and_archive_failure_recovery_restarts_only_approved_id(self):
        for fail_step in ("snapshot", "archive"):
            with self.subTest(fail_step=fail_step), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                repository = root / "servarr"
                discovery = repository / "machines/discovery"
                evidence = root / "evidence"
                snapshot = root / "snapshot"
                vault_env = root / "networking.env"
                cert = discovery / "config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem"
                dns = discovery / "config/swag/dns-conf/cloudflare.ini"
                for path in (discovery / "networking.yml", discovery / ".env", vault_env, cert, dns):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("fixture")
                source = ADOPT.read_text()
                for old, new in {
                    "readonly repository=/home/erik/servarr": f"readonly repository={repository}",
                    "readonly vault_env=/run/vault-agent/networking.env": f"readonly vault_env={vault_env}",
                    "readonly evidence=/var/lib/stateful-stack-migrations/p1-swag": f"readonly evidence={evidence}",
                    "readonly snapshot=/home/.snapshots/stateful-stack-p1-swag": f"readonly snapshot={snapshot}",
                    "readonly cert=/home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem": f"readonly cert={cert}",
                    "readonly dns_ini=/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini": f"readonly dns_ini={dns}",
                }.items():
                    source = source.replace(old, new)
                script = root / "adopt.sh"
                script.write_text(source)
                authorization = authorization_fixture()
                authorization_path = root / "authorization.json"
                authorization_path.write_text(json.dumps(authorization))
                inventory = json.loads(INVENTORY.read_text())
                running = {"containers": inventory["containers"]}
                stopped = json.loads(json.dumps(running))
                next(item for item in stopped["containers"] if item["name"] == "swag")["state"] = "exited"
                raw_swag = json.loads(RAW.read_text())["container_inspects"][0]
                raw_swag["Config"]["Labels"]["com.docker.compose.project.working_dir"] = str(discovery)
                raw_swag["State"]["Health"] = {"Status": "healthy"}
                state = root / "state"
                state.write_text("running")
                log = root / "commands.log"
                compose_log = root / "compose.log"
                physical_source = str(discovery / "config/swag")
                ledger_template = root / "ledger.json"
                ledger_template.write_text(json.dumps({
                    "archive_id": str(evidence / "swag-config.tar.zst"), "compose_owner": str(discovery),
                    "compose_project": "networking", "container": "swag",
                    "copy_destination": str(evidence / "restore-only-after-approval"), "expected_downtime": "up to 2 minutes",
                    "git_commit": "5" * 40, "image_digest": "sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d",
                    "image_tag": "lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d",
                    "mount_target": "/config", "ownership": "1000:1000", "physical_source": physical_source,
                    "physical_volume": physical_source, "recorded_at": "2026-07-15T00:00:00Z",
                    "rollback_command": "discovery-stateful-swag-adopt rollback --manifest-sha APPROVED_MANIFEST_SHA256",
                    "size_bytes": 1, "snapshot_id": str(snapshot), "snapshot_source": "/home", "version": 1, "volume_type": "bind",
                }))
                inventory_json = json.dumps(inventory, separators=(",", ":"))
                running_json = json.dumps(running, separators=(",", ":"))
                stopped_json = json.dumps(stopped, separators=(",", ":"))
                inspect_json = json.dumps([raw_swag], separators=(",", ":"))
                stubs = {
                    "id": "#!/bin/sh\necho 0\n",
                    "discovery-stateful-swag-preflight": "#!/bin/sh\necho '{\"status\":\"binding-valid\"}'\n",
                    "discovery-stateful-swag-inventory": f"#!/bin/sh\necho inventory:$1 >>\"$COMMAND_LOG\"\nif [ \"$1\" = capture-runtime ]; then if grep -q stopped \"$STATE\"; then echo '{stopped_json}'; else echo '{running_json}'; fi; else echo '{inventory_json}'; fi\n",
                    "discovery-stateful-stack-ops": "#!/bin/sh\necho ops:$1 >>\"$COMMAND_LOG\"\nif [ \"$1\" = ledger-create ]; then cp \"$LEDGER_TEMPLATE\" \"$2\"; exit 0; fi\n[ \"$1\" = \"$FAIL_STEP\" ] && exit 88\nexit 0\n",
                    "docker": f"#!/bin/sh\necho docker:$* >>\"$COMMAND_LOG\"\nif [ \"$1\" = inspect ] && [ \"$2\" = swag ]; then echo '{inspect_json}'; exit 0; fi\nif [ \"$1\" = inspect ] && [ \"$2\" = --format ]; then grep -q running \"$STATE\" && echo true || echo false; exit 0; fi\nif [ \"$1\" = stop ]; then echo stopped >\"$STATE\"; exit 0; fi\nif [ \"$1\" = start ]; then echo running >\"$STATE\"; exit 0; fi\nexit 99\n",
                    "docker-compose": f"#!/bin/sh\necho compose >>'{compose_log}'\n",
                    "openssl": "#!/bin/sh\ncase \"$*\" in *fingerprint*) echo 'sha256 Fingerprint=AA' ;; *startdate*) echo 'notBefore=Jul 1 00:00:00 2026 GMT' ;; *enddate*) echo 'notAfter=Oct 12 00:00:00 2026 GMT' ;; esac\n",
                }
                for name, body in stubs.items():
                    path = root / name
                    path.write_text(body)
                    path.chmod(0o755)
                env = os.environ.copy()
                env.update({
                    "COMMAND_LOG": str(log), "STATE": str(state), "LEDGER_TEMPLATE": str(ledger_template),
                    "FAIL_STEP": fail_step,
                    "PATH": f"{root}:{pathlib.Path.home() / '.nix-profile/bin'}:/run/current-system/sw/bin:/usr/bin:/bin",
                })
                execute = subprocess.run(
                    ["bash", str(script), "execute", "--authorization", str(authorization_path), "--manifest-sha", authorization["manifest_sha256"]],
                    check=False, capture_output=True, text=True, env=env,
                )
                self.assertEqual(execute.returncode, 1, msg=execute.stderr)
                self.assertIn("recover-pre-adoption --manifest-sha", execute.stderr)
                self.assertEqual(state.read_text().strip(), "stopped")
                recover = subprocess.run(
                    ["bash", str(script), "recover-pre-adoption", "--manifest-sha", authorization["manifest_sha256"]],
                    check=False, capture_output=True, text=True, env=env,
                )
                self.assertEqual(recover.returncode, 0, msg=recover.stderr)
                self.assertEqual(state.read_text().strip(), "running")
                self.assertIn("docker:start " + "1" * 64, log.read_text())
                self.assertFalse(compose_log.exists())


if __name__ == "__main__":
    unittest.main()
