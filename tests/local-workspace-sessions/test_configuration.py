"""Bind independent-window and safe-transition scenarios to evaluated Nix."""
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SESSIONS = {}
for prefix, workspace in (("w", 2), ("l", 7)):
    SESSIONS.update({f"{prefix}{i}": workspace for i in range(1, 9)})

class Configuration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        expression = '''c: let h = c.home-manager.users.erik; in {
          units = builtins.listToAttrs (map (name: {
            inherit name; value = h.systemd.user.services.${name};
          }) (builtins.filter (name: builtins.match "(desktop-.*|opencode-.*|tmux-save.*)" name != null)
            (builtins.attrNames h.systemd.user.services)));
          timers = h.systemd.user.timers;
          linger = c.users.users.erik.linger;
          rules = h.wayland.windowManager.hyprland.settings.window_rule;
          workspaceRules = h.wayland.windowManager.hyprland.settings.workspace_rule;
          lua = h.xdg.configFile."hypr/hyprland.lua".text;
          binds = h.wayland.windowManager.hyprland.settings.bind;
          hooks = h.wayland.windowManager.hyprland.settings.on;
          terminal = h.wayland.windowManager.hyprland.settings.terminal;
          editor = h.wayland.windowManager.hyprland.settings.terminalEditor or {};
          yazi = h.wayland.windowManager.hyprland.settings.fileManagerTui;
          tmuxConfig = h.xdg.configFile."tmux/desktop-workspaces.conf".text or "";
          opencode = toString h.programs.opencode.package;
          opencodeConfig = toString h.xdg.configFile."opencode/opencode.json".source;
          home = h.home.homeDirectory;
          configHome = h.xdg.configHome;
          dataHome = h.xdg.dataHome;
          stateHome = h.xdg.stateHome;
          cacheHome = h.xdg.cacheHome;
          legacyPrivacy = h.home.activation.protectLegacyOpencodeHomelab or null;
          legacyRtkRetirement = h.home.activation.retireLegacyOpencodeRtk or null;
          wrappers = map (p: { name = p.name; path = toString p; drv = p.drvPath; })
            (builtins.filter (p: builtins.elem p.name ["ol" "ow" "opencode-backend-homelab" "opencode-backend-dataplatform"])
              h.home.packages);
        }'''
        result = subprocess.run(["nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config", "--apply", expression],
            cwd=ROOT, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.config = json.loads(result.stdout)

    def test_activation_secures_only_existing_legacy_homelab_database(self):
        activation = self.config["legacyPrivacy"]
        self.assertIsNotNone(activation, "permission-only legacy homelab activation missing")
        self.assertIn("writeBoundary", activation["after"])
        with tempfile.TemporaryDirectory(prefix="opencode-legacy-mode-contract-") as temporary:
            home = Path(temporary) / "home"
            database = Path(self.config["dataHome"].replace(self.config["home"], str(home))) / "opencode/opencode-homelab.db"
            work_database = database.with_name("opencode-dataplatform.db")
            script = activation["data"].replace(self.config["home"], str(home))
            def activate():
                result = subprocess.run(["bash", "-euc", 'run() { "$@"; };\n' + script],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "", "activation must not print database data")
            activate()
            self.assertFalse(database.exists(), "activation must not create an absent V1 database")
            database.parent.mkdir(parents=True)
            database.write_bytes(b"synthetic legacy homelab history")
            database.chmod(0o644)
            work_database.write_bytes(b"synthetic legacy dataplatform history")
            work_database.chmod(0o600)
            before = database.stat()
            work_before = work_database.stat()
            for _ in range(2):
                activate()
                after = database.stat()
                self.assertEqual(after.st_mode & 0o777, 0o600)
                self.assertEqual((after.st_ino, after.st_size, after.st_mtime_ns),
                                 (before.st_ino, before.st_size, before.st_mtime_ns))
                self.assertEqual(work_database.stat(), work_before, "dataplatform metadata must stay untouched")

    def test_native_v2_backends_have_isolated_state_and_no_desktop_lifecycle(self):
        units = self.config["units"]
        roots = set()
        for project in ("homelab", "dataplatform"):
            name = f"opencode-{project}"
            self.assertTrue(name in units, f"native V2 backend missing: {name}")
            unit = units[name]
            self.assertNotEqual(unit["Unit"].get("X-SwitchMethod"), "keep-old")
            triggers = unit["Unit"].get("X-Restart-Triggers")
            self.assertEqual(triggers[0], self.config["opencodeConfig"])
            self.assertEqual(len(triggers), 2, "legacy retirement must refresh cached plugin inventory")
            self.assertEqual(triggers[1], shlex.split(self.config["legacyRtkRetirement"]["data"])[1])
            self.assertFalse(unit["Unit"].get("PartOf"))
            self.assertFalse(unit["Unit"].get("BindsTo"))
            self.assertEqual(unit["Install"]["WantedBy"], ["default.target"])
            self.assertEqual(unit["Service"]["UMask"], "0077")
            environment = dict(item.split("=", 1) for item in unit["Service"]["Environment"])
            self.assertEqual(environment.get("OPENCODE_DISABLE_CLAUDE_CODE"), "1")
            self.assertEqual(environment["OPENCODE_DB"],
                             f'{self.config["dataHome"]}/opencode-v2-backends/{project}/opencode.db')
            for variable, root in (("XDG_DATA_HOME", "dataHome"), ("XDG_STATE_HOME", "stateHome"),
                                   ("XDG_CACHE_HOME", "cacheHome")):
                path = environment[variable]
                self.assertEqual(path, f'{self.config[root]}/opencode-v2-backends/{project}')
                self.assertTrue(Path(path).is_absolute())
                roots.add((variable, path))
            self.assertTrue(environment["PATH"].startswith("/run/wrappers/bin:"))
            for existing in ("desktop-tmux", "desktop-session-homelab-code", "desktop-session-dataplatform-code"):
                self.assertTrue(units[existing]["Service"]["Environment"][0].startswith("PATH=/run/wrappers/bin:"))
        self.assertEqual(len(roots), 6)

    def test_legacy_rtk_retirement_preserves_unknown_files_and_backup(self):
        activation = self.config["legacyRtkRetirement"]
        self.assertIsNotNone(activation, "guarded legacy RTK retirement missing")
        self.assertIn("writeBoundary", activation["after"])
        self.assertIn("reloadSystemd", activation["before"], "retire legacy before refreshing backend inventory")
        script_path = Path(shlex.split(activation["data"])[1])
        build = subprocess.run(["nix", "build", "--no-link", "--impure", "--expr",
            '''let f = builtins.getFlake (toString ./.); in builtins.elemAt
            f.nixosConfigurations.endeavour.config.home-manager.users.erik.systemd.user.services.opencode-homelab.Unit.X-Restart-Triggers 1''',
            "--builders", ""], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stderr)
        original = Path(subprocess.check_output(["nix", "eval", "--raw", "--impure", "--expr",
            'let f = builtins.getFlake (toString ./.); in toString (f.inputs.opencode-flake + "/plugins/rtk.ts")'],
            cwd=ROOT, text=True).strip())
        known = original.read_bytes()
        with tempfile.TemporaryDirectory(prefix="opencode-legacy-plugin-") as temporary:
            home = Path(temporary) / "home"
            legacy = Path(self.config["configHome"].replace(self.config["home"], str(home))) / "opencode/plugins/rtk.ts"
            backup = Path(self.config["stateHome"].replace(self.config["home"], str(home))) / "opencode-v2-migration/rtk-v1.ts"
            script = script_path.read_text().replace(self.config["home"], str(home))
            # Substitute only the immutable-store guard prefix for disposable fixture targets.
            store = Path(temporary) / "store"
            store.mkdir()
            script = script.replace("/nix/store/*", str(store) + "/*")
            known_target = store / "known-rtk.ts"
            known_target.write_bytes(known)
            unknown_target = store / "custom-rtk.ts"
            unknown_target.write_text("custom plugin")
            def activate():
                result = subprocess.run(["bash", "-euc", script], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "", "retirement must not hide a failed command")
            activate()
            self.assertFalse(backup.exists())
            legacy.parent.mkdir(parents=True)
            legacy.write_bytes(known)
            activate()
            self.assertTrue(legacy.is_file(), "regular files must be left untouched")
            legacy.unlink()
            legacy.symlink_to(unknown_target)
            activate()
            self.assertTrue(legacy.is_symlink(), "unknown symlink contents must be left untouched")
            legacy.unlink()
            outside_store = Path(temporary) / "known-rtk.ts"
            outside_store.write_bytes(known)
            legacy.symlink_to(outside_store)
            activate()
            self.assertTrue(legacy.is_symlink(), "non-store symlink must be left untouched")
            legacy.unlink()
            legacy.symlink_to(known_target)
            backup.parent.mkdir(parents=True)
            backup.symlink_to(unknown_target)
            activate()
            self.assertTrue(legacy.is_symlink())
            self.assertEqual(unknown_target.read_text(), "custom plugin")
            backup.unlink()
            backup.write_text("existing recovery data")
            backup.chmod(0o600)
            activate()
            self.assertTrue(legacy.is_symlink())
            self.assertEqual(backup.read_text(), "existing recovery data")
            backup.unlink()
            backup.write_bytes(known)
            backup.chmod(0o644)
            activate()
            self.assertTrue(legacy.is_symlink(), "insecure existing backup must preserve legacy")
            self.assertEqual(backup.stat().st_mode & 0o777, 0o644)
            backup.unlink()
            activate()
            self.assertFalse(legacy.is_symlink())
            self.assertEqual(backup.read_bytes(), known)
            self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
            activate()
            self.assertEqual(backup.read_bytes(), known)

    def test_backend_credentials_routing_and_native_client_forwarding(self):
        for project in ("homelab", "dataplatform"):
            self.assertTrue(f"opencode-{project}" in self.config["units"], "backend needed before wrapper checks")
        wrappers = {p["name"]: p for p in self.config["wrappers"]}
        expected = {"ol", "ow", "opencode-backend-homelab", "opencode-backend-dataplatform"}
        self.assertEqual(set(wrappers), expected)
        build = subprocess.run(["nix", "build", "--no-link", "--builders", "", *[p["drv"] + "^out" for p in wrappers.values()]],
                               cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stderr)
        with tempfile.TemporaryDirectory(prefix="opencode-wrapper-contract-") as temporary:
            root = Path(temporary)
            stub = root / "opencode"
            stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
print(json.dumps({"args": sys.argv[1:], "password": bool(os.environ.get("OPENCODE_PASSWORD")),
    "keys": {key: os.environ.get(key) == "fixture-scoped-key" for key in
             ("OPENCODE_LITELLM_KEY", "OPENCODE_WORK_KEY") if key in os.environ},
    "config": json.loads(os.environ.get("OPENCODE_CONFIG_CONTENT", "{}")),
    "configDir": os.environ.get("OPENCODE_CONFIG_DIR"),
    "projectDisabled": os.environ.get("OPENCODE_DISABLE_PROJECT_CONFIG"),
    "l2Model": os.environ.get("OPENCODE_THREE_LEVEL_L2_MODEL"),
    "db": os.environ.get("OPENCODE_DB")}))
''')
            stub.chmod(0o700)
            secrets = root / "secrets"
            secrets.mkdir()
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith(("OPENCODE_", "XDG_"))}
            environment["HOME"] = str(root / "home")
            environment["OPENCODE_LITELLM_KEY"] = "inherited-not-sanctioned"
            environment["OPENCODE_WORK_KEY"] = "inherited-not-sanctioned"
            def run(name, args=(), service_environment=()):
                script = Path(wrappers[name]["path"]) / "bin" / name
                text = script.read_text()
                self.assertIn(self.config["opencode"] + "/bin/opencode", text)
                text = text.replace(self.config["home"], environment["HOME"])
                text = text.replace(self.config["opencode"] + "/bin/opencode", str(stub))
                text = text.replace("/run/secrets/opencode", str(secrets))
                candidate = root / name
                candidate.write_text(text)
                candidate.chmod(0o700)
                env = dict(environment)
                env.update(item.replace(self.config["home"], environment["HOME"]).split("=", 1)
                           for item in service_environment)
                result = subprocess.run([str(candidate), *args], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)
            for project, client, port, provider, key_file, key_variable in (
                ("homelab", "ol", 4096, "litellm", "litellm_key", "OPENCODE_LITELLM_KEY"),
                ("dataplatform", "ow", 4097, "work", "work_key", "OPENCODE_WORK_KEY")):
                service = self.config["units"][f"opencode-{project}"]["Service"]
                native_env = dict(environment)
                native_env.update(item.replace(self.config["home"], environment["HOME"]).split("=", 1)
                                  for item in service["Environment"])
                for selector, expected_path in (("db", native_env["OPENCODE_DB"]),
                    ("data", native_env["XDG_DATA_HOME"] + "/opencode"),
                    ("state", native_env["XDG_STATE_HOME"] + "/opencode"),
                    ("cache", native_env["XDG_CACHE_HOME"] + "/opencode")):
                    result = subprocess.run([self.config["opencode"] + "/bin/opencode", "debug", "paths", selector],
                                            env=native_env, cwd=root, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), expected_path)
                self.assertFalse(Path(native_env["OPENCODE_DB"]).exists(), "debug paths must not open a database")
                self.assertEqual(len(service["ExecStart"]), 1)
                command = shlex.split(service["ExecStart"][0])
                backend = f"opencode-backend-{project}"
                self.assertEqual(command[0], wrappers[backend]["path"] + "/bin/" + backend)
                absent = run(backend, command[1:], service["Environment"])
                self.assertEqual(absent["keys"], {}, "missing sops files must omit keys, not inherit fallback")
                self.assertEqual(absent["db"], native_env["OPENCODE_DB"])
                self.assertEqual(absent["args"], ["serve", "--hostname", "127.0.0.1", "--port", str(port)])
                self.assertEqual(absent["config"]["model"], provider + "/deepseek-v4.1-flash")
                self.assertEqual(absent["config"].get("small_model"), provider + "/deepseek-v4.1-flash")
                self.assertEqual(absent["config"]["default_agent"], "pilot-l1")
                self.assertEqual(sorted(absent["config"]["agents"]), ["pilot-l1", "pilot-l2", "pilot-l3"])
                self.assertEqual(absent["config"]["agents"]["pilot-l1"]["model"],
                                 provider + "/deepseek-v4.1-flash" + ("#max" if project == "homelab" else ""))
                self.assertEqual(absent["config"]["agents"]["pilot-l2"]["model"],
                                 provider + "/deepseek-v4.1-flash" + ("#high" if project == "homelab" else ""))
                self.assertEqual(absent["l2Model"], absent["config"]["agents"]["pilot-l2"]["model"])
                provider_rules = [rule for rule in absent["config"]["experimental"]["policies"]
                                  if rule["action"] == "provider.use"]
                self.assertEqual(provider_rules, [
                    {"action": "provider.use", "resource": "*", "effect": "deny"},
                    {"action": "provider.use", "resource": provider, "effect": "allow"},
                    {"action": "provider.use", "resource": "opencode-go", "effect": "allow"},
                    {"action": "provider.use", "resource": "openai", "effect": "allow"}])
                self.assertTrue(any("three-level" in plugin for plugin in absent["config"]["plugins"]))
                self.assertEqual(absent["projectDisabled"], "1")
                self.assertEqual(absent["configDir"], self.config["configHome"].replace(self.config["home"], environment["HOME"]) + "/opencode")
                self.assertTrue(absent["password"])
                auth_file = Path(environment["HOME"]) / ".local/state/opencode-v2-backends" / project / "server-password"
                self.assertEqual(auth_file.stat().st_mode & 0o777, 0o600)
                before = auth_file.read_bytes()
                (secrets / key_file).write_text("fixture-scoped-key\n")
                present = run(backend, command[1:], service["Environment"])
                self.assertEqual(present["keys"], {key_variable: True})
                self.assertEqual(auth_file.read_bytes(), before, "backend restart must retain client authentication")
                (secrets / key_file).unlink()
                forwarded = run(client, ["--session", "session with spaces", "--model", "custom/model"])
                self.assertEqual(forwarded["args"], ["--auto", "--server", f"http://127.0.0.1:{port}",
                    "--session", "session with spaces", "--model", "custom/model"])
                self.assertTrue(forwarded["password"])

    def test_default_layout_and_monitor_rules_are_preserved(self):
        rules = self.config["workspaceRules"]
        self.assertFalse(any(rule.get("layout") == "lua:workspace-grid" for rule in rules))
        self.assertTrue(any(rule["workspace"] == "1" and rule.get("monitor") for rule in rules))
        self.assertNotIn("hl.layout.register(", self.config["lua"])

    def test_one_server_and_sixteen_independent_window_units(self):
        """Independent defaults and backend ownership."""
        units = self.config["units"]
        self.assertIn("desktop-tmux", units, "foreground tmux backend missing")
        backend = units["desktop-tmux"]
        command = str(backend["Service"]["ExecStart"])
        self.assertIn("tmux -D -L workspace-desktop", command)
        self.assertNotIn("start-server", command)
        self.assertEqual(backend["Unit"]["X-SwitchMethod"], "keep-old")
        self.assertFalse(backend["Unit"].get("PartOf"))
        self.assertFalse(backend["Unit"].get("BindsTo"))
        self.assertTrue(self.config["linger"])
        for setting in ("exit-empty off", "exit-unattached off", "destroy-unattached off"):
            self.assertIn(setting, self.config["tmuxConfig"])
        self.assertEqual({n for n in units if n.startswith("desktop-window-")},
                         {f"desktop-window-{n}" for n in SESSIONS})
        for name in SESSIONS:
            frontend = units[f"desktop-window-{name}"]
            self.assertIn("desktop-tmux.service", frontend["Unit"]["Requires"])
            self.assertIn("desktop-tmux.service", frontend["Unit"]["After"])
            self.assertIn("graphical-session.target", frontend["Unit"]["PartOf"])
            self.assertEqual(frontend["Service"].get("Restart", "no"), "no")
            self.assertIn(f"bootstrap {name}", str(frontend["Service"]["ExecStartPre"]))
            self.assertIn(f"tmux -N -L workspace-desktop attach-session -t ={name}",
                          str(frontend["Service"]["ExecStart"]))

    def test_sessions_are_saved_and_restored_across_reboots(self):
        """Resurrect snapshot is restored at server start and saved periodically."""
        backend = self.config["units"]["desktop-tmux"]
        self.assertIn("desktop-workspaces restore", str(backend["Service"]["ExecStartPost"]))
        self.assertIn("@resurrect-dir", self.config["tmuxConfig"])
        self.assertIn("resurrect.tmux", self.config["tmuxConfig"])
        self.assertIn("desktop-workspaces save", json.dumps(self.config["units"]["tmux-save"]["Service"]["ExecStart"]))
        shutdown = self.config["units"]["tmux-save-shutdown"]
        self.assertIn("shutdown.target", shutdown["Unit"]["Before"])
        self.assertIn("shutdown.target", shutdown["Install"]["WantedBy"])
        timer = self.config["timers"]["tmux-save"]
        self.assertEqual(timer["Timer"]["Unit"], "tmux-save.service")
        self.assertIn("timers.target", timer["Install"]["WantedBy"])

    def test_preserve_old_herdr_backends_during_transition(self):
        """Removing attachment windows must not remove the live servers."""
        for project in ("dataplatform", "homelab"):
            for kind in ("code", "review"):
                name = f"{project}-{kind}"
                backend = self.config["units"][f"desktop-session-{name}"]
                self.assertEqual(backend["Unit"]["X-SwitchMethod"], "keep-old")
                self.assertFalse(backend["Unit"].get("PartOf"))
                self.assertFalse(backend.get("Install", {}).get("WantedBy"))
                self.assertIn(f"--session {name} server", str(backend["Service"]["ExecStart"]))
                self.assertNotIn(f"desktop-window-{name}", self.config["units"])

    def test_sixteen_class_rules_and_both_recovery_triggers(self):
        rules = self.config["rules"]
        for name, workspace in SESSIONS.items():
            matches = [r for r in rules if name in r.get("match", {}).get("class", "")]
            self.assertEqual(len(matches), 1, f"missing stable class rule for {name}")
            self.assertEqual(matches[0]["workspace"], f"{workspace} silent")
        recovery = [b for b in self.config["binds"] if b.get("_args", [None])[0] == "SUPER + SHIFT + R"]
        self.assertEqual(len(recovery), 1)
        self.assertIn("desktop-workspaces recover", json.dumps(recovery))
        self.assertIn("desktop-workspaces recover", json.dumps(self.config["hooks"]))

    def test_route_shortcuts_and_limit_rollout(self):
        self.assertIn("desktop-workspaces launch shell", json.dumps(self.config["terminal"]))
        self.assertIn("desktop-workspaces launch nvim", json.dumps(self.config["editor"]))
        self.assertIn("desktop-workspaces launch yazi", json.dumps(self.config["yazi"]))
        users = {str(p.relative_to(ROOT)) for p in (ROOT / "modules").rglob("*.nix")
                 if "m.home.desktop-workspaces" in p.read_text() or "m.nixos.desktop-workspaces" in p.read_text()}
        self.assertEqual(users, {"modules/hosts/endeavour/default.nix"})

if __name__ == "__main__":
    unittest.main()
