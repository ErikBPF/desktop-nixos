#!/usr/bin/env python3
"""Synthetic only: no production SSH, units, passwords, homes or repositories."""
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import types
import sys
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/hermes-state-backup.sh"
module = types.ModuleType("backup")
exec(SCRIPT.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0], module.__dict__)
DATABASES = []
INTERPRETER = "/nix/store/" + "a" * 32 + "-python3-3.13.12/bin/python3"


def lifecycle(failure=None, inactive=False, recovery=None, health_active=False, absent_timer=False):
    events = []
    observed = []
    prior = {"timer": "absent" if absent_timer else "inactive" if inactive else "active",
             "health": "absent" if absent_timer else "active" if health_active else "inactive",
             "writer": "inactive" if inactive else "active"}
    restored = dict(prior, health="absent" if absent_timer else "inactive")
    if recovery == "writer-inactive":
        restored["writer"] = "inactive"
    elif recovery == "inactive-active":
        restored["writer"] = "active"
    elif recovery in ("timer-inactive", "timer-absence"):
        restored["timer"] = "inactive"
    elif recovery == "unexpected":
        restored["writer"] = "failed"

    def states():
        observed.append((module.PHASE, len(events)))
        if module.PHASE == "recovery":
            if recovery == "get-failure":
                raise PermissionError("FAKE_SECRET")
            return restored
        if len(observed) == 1:
            return prior
        return {name: "absent" if value == "absent" else "inactive" for name, value in prior.items()}
    # External host operations are necessarily faked; supervisor itself is real.
    def unit(action, name):
        events.append((action, name))
        if failure == action + "-" + name:
            raise RuntimeError("synthetic private fixture")

    def operation(name):
        events.append((name, "" if name == "archive" else True))
        if failure == name:
            raise TimeoutError("synthetic private fixture")

    with patch.object(module.signal, "signal"), patch.object(module.signal, "alarm"), patch.object(module, "preflight"), patch.object(
        module, "states", side_effect=states
    ), patch.object(module, "TIMERS", ["timer"], create=True), patch.object(
        module, "HEALTH", ["health"], create=True
    ), patch.object(module, "WRITERS", ["writer"], create=True), patch.object(
        module, "unit", side_effect=unit, create=True
    ), patch.object(
        module, "send_archive", side_effect=lambda: operation("archive")
    ), patch.object(module, "receive_archive", side_effect=lambda compare: operation("verify")):
        failed = False
        error = None
        try:
            module.remote("backup")
        except (RuntimeError, TimeoutError) as caught:
            failed = True
            error = caught
    assert failed == bool(failure or recovery), (failure, recovery, "recovery must be observed")
    if recovery:
        assert type(error) is RuntimeError and module.diagnostic(error) == {"phase": "recovery", "class": "RuntimeError"}
    if not failure:
        expected = [("stop", name) for name in ("timer", "health", "writer") if prior[name] != "absent"]
        expected += [("archive", ""), ("verify", True)]
        assert events[:len(expected)] == expected, events
    if inactive:
        assert not any(event[0] == "start" for event in events), events
    elif not absent_timer:
        assert events[-2:] == [("start", "writer"), ("start", "timer")], events
    else:
        assert events[-1:] == [("start", "writer")], events
    assert observed[-1] == ("recovery", len(events)), "post-GET must follow all recovery attempts"
    assert len(observed) == (2 if failure and failure.startswith("stop-") else 3)


def rejects(action):
    try:
        action()
    except Exception:
        return
    raise AssertionError("unsafe input accepted")


def readonly_modes():
    prior = {name: "inactive" for name in module.WRITERS + module.TIMERS + module.HEALTH}
    for mode in ("preflight", "rehearse"):
        with patch.object(module, "preflight"), patch.object(module, "states", return_value=prior) as getter, patch.object(
            module, "unit"
        ) as units, patch.object(module, "receive_archive") as receive, patch.object(
            module.signal, "alarm"
        ), patch.object(module.sys, "stdout", io.StringIO()):
            module.remote(mode)
        units.assert_not_called()
        assert getter.call_count == (1 if mode == "preflight" else 0)
        if mode == "rehearse":
            receive.assert_called_once_with(False)
        else:
            receive.assert_not_called()


def fixture(root):
    for name in module.NAMES:
        home = root / name
        home.mkdir()
        (home / "auth.json").write_text("SYNTHETIC-PRIVATE-CONTENT")
        (home / "public-link").symlink_to("/nix/store/synthetic-public-config")
        db = sqlite3.connect(home / "state.db")
        DATABASES.append(db)
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("CREATE TABLE messages(body TEXT)")
        db.execute("INSERT INTO messages VALUES ('SYNTHETIC-PRIVATE-CONTENT')")
        db.commit()
        assert (home / "state.db-wal").stat().st_size > 0
        assert (home / "state.db-shm").is_file()


def archive_security(tmp):
    root = tmp / "source"
    root.mkdir()
    fixture(root)
    archive = tmp / "good.tar"
    subprocess.run(["tar", "--format=pax", "-C", str(root), "-cpf", str(archive), *module.NAMES], check=True)
    restored = tmp / "restored"
    restored.mkdir(mode=0o700)
    with patch.object(module, "ROOT", root):
        module.extract(archive, restored)
        module.verify(restored, True)
        (restored / module.NAMES[0] / "auth.json").write_text("changed")
        rejects(lambda: module.verify(restored, True))
        (restored / module.NAMES[0] / "state.db").write_bytes(b"corrupt")
        (restored / module.NAMES[0] / "state.db-wal").write_bytes(b"corrupt")
        rejects(lambda: module.verify(restored, False))
    for member_name, kind in [("../escape", "file"), ("/escape", "file"),
                              ("hermes-argus/link/escape", "parent"),
                              ("hermes-argus/state.db", "symlink"),
                              ("hermes-argus/state.db-shm", "symlink"),
                              ("hermes-argus/hard", "hardlink"), ("other/file", "file")]:
        evil = tmp / "evil.tar"
        with tarfile.open(evil, "w") as tar:
            for name in module.NAMES:
                directory = tarfile.TarInfo(name)
                directory.type = tarfile.DIRTYPE
                tar.addfile(directory)
                db = tarfile.TarInfo(name + "/state.db")
                tar.addfile(db, io.BytesIO())
            if kind == "parent":
                link = tarfile.TarInfo("hermes-argus/link")
                link.type = tarfile.SYMTYPE
                link.linkname = str(tmp)
                tar.addfile(link)
            member = tarfile.TarInfo(member_name)
            if kind in ("symlink", "hardlink"):
                member.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                member.linkname = str(tmp / "escape")
            tar.addfile(member, io.BytesIO())
        rejects(lambda: module.extract(evil, restored))
        assert not (tmp / "escape").exists()
    return root, archive


def encrypted(tmp, root, archive):
    restic = shutil.which("restic")
    if not restic:
        raise RuntimeError("restic unavailable")
    password = tmp / "fake-password"
    password.write_text("SYNTHETIC-TEST-PASSWORD-NOT-A-PRODUCTION-KEY")
    password.chmod(0o600)
    env = dict(os.environ, RESTIC_REPOSITORY=str(tmp / "encrypted-repository"), RESTIC_PASSWORD_FILE=str(password))
    def command(*args, **kwargs):
        return subprocess.run([restic, *args], env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60, **kwargs)
    assert command("init").returncode == 0
    result = command("backup", "--stdin", "--stdin-filename", module.ARCHIVE, "--tag", module.TAG,
                     "--json", input=archive.read_bytes())
    assert result.returncode == 0
    import json
    snapshot = [json.loads(line)["snapshot_id"] for line in result.stdout.splitlines()
                if json.loads(line).get("message_type") == "summary"][0]
    module.valid_id(snapshot)
    restored = command("dump", snapshot, module.ARCHIVE)
    assert restored.returncode == 0
    output = tmp / "encrypted-restore"
    output.mkdir(mode=0o700)
    restored_tar = tmp / "restored.tar"
    restored_tar.write_bytes(restored.stdout)
    with patch.object(module, "ROOT", root):
        module.extract(restored_tar, output)
        module.verify(output, True)
    password.write_text("SYNTHETIC-WRONG-PASSWORD")
    assert command("dump", snapshot, module.ARCHIVE).returncode != 0
    assert command("snapshots", "--json").returncode != 0
    assert not any(b"SYNTHETIC-PRIVATE-CONTENT" in p.read_bytes()
                   for p in (tmp / "encrypted-repository").rglob("*") if p.is_file())
    print("PASS hermes-state-backup-encrypted-roundtrip")


def transport(tmp, root):
    """Actual helper subprocess/pipe/supervisor, real encryption, fake SSH/units.

    No production operation is reachable: wrappers intercept every external hop.
    """
    actual_restic = shutil.which("restic")
    if not actual_restic:
        raise RuntimeError("restic unavailable")
    tools = tmp / "tools"
    tools.mkdir()
    state = tmp / "units.json"
    events = tmp / "events.jsonl"
    initial = {name: "active" for name in module.TIMERS + module.WRITERS}
    initial.update({name: "inactive" for name in module.HEALTH})
    state.write_text(json.dumps(initial))
    repository = tmp / "transport-repo"
    password = tmp / "transport-password"
    password.write_text("SYNTHETIC-TRANSPORT-TEST-KEY")
    password.chmod(0o600)
    environment = dict(os.environ, PATH=str(tools) + ":" + os.environ["PATH"],
                       RESTIC_REPOSITORY=str(repository), RESTIC_PASSWORD_FILE=str(password))
    assert subprocess.run([actual_restic, "init"], env=environment, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0
    wrappers = {
        "ssh": f'''import os, shlex, sys, subprocess
command = sys.argv[-1]
if command.startswith("sudo -n sh -c"):
    if os.environ.get("SYNTHETIC_FAIL") == "credential":
        sys.stderr.write("FAKE_SECRET")
        sys.exit(23)
    sys.stdout.write("SYNTHETIC-TRANSPORT-TEST-KEY")
else:
    if os.environ.get("SYNTHETIC_FAIL") == "interpreter":
        sys.stderr.write("FAKE_SECRET interpreter unavailable")
        sys.exit(127)
    if os.environ.get("SYNTHETIC_FAIL") == "unknown":
        sys.stdout.write("FAKE_SECRET unsafe SSH output")
        sys.stderr.write("FAKE_SECRET unsafe SSH error")
        sys.exit(7)
    args = shlex.split(command)
    source = args[args.index("-c") + 1]
    source = source.replace('Path("/home/erik/homelab/apps")', {('Path(' + repr(str(root)) + ')')!r})
    source = source.replace("LIMIT = 600", "LIMIT = 3")
    if os.environ.get("SYNTHETIC_FAIL") == "supervisor":
        source = source.replace('def preflight():', 'def preflight():\\n    raise PermissionError("FAKE_SECRET")')
    if os.environ.get("SYNTHETIC_FAIL") == "timeout":
        source = source.replace("LIMIT = 3", "LIMIT = 1")
    if os.environ.get("SYNTHETIC_FAIL") == "frame-negative":
        source = source.replace('HERMES1 {{length}}', 'HERMES1 -1')
    if os.environ.get("SYNTHETIC_FAIL") == "frame-truncated":
        source = source.replace('shutil.copyfileobj(stream, sys.stdout.buffer)', 'sys.stdout.buffer.write(stream.read(10))')
    if os.environ.get("SYNTHETIC_FAIL") == "frame-trailing":
        source = source.replace('sys.stdout.buffer.write(FRAME_END)', 'sys.stdout.buffer.write(b"EXTRA" + FRAME_END)')
    # SSH relay retains its own stdout FD while worker waits for restore input.
    child = subprocess.Popen([sys.executable, "-c", source, "--remote", args[-1]])
    sys.exit(child.wait())
''',
        "restic": f'''import os, sys, signal, time
args = sys.argv[1:]
if args[:1] == ["-o"]:
    args = args[2:]
os.environ["RESTIC_REPOSITORY"] = {str(repository)!r}
if args[0] == "backup" and os.environ.get("SYNTHETIC_FAIL") == "interrupt":
    os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(2)
if args[0] == "dump" and os.environ.get("SYNTHETIC_FAIL") == "timeout":
    time.sleep(2)
if args[0] == os.environ.get("SYNTHETIC_FAIL"):
    sys.stderr.write("SYNTHETIC-PRIVATE-CONTENT")
    sys.exit(2)
os.execv({actual_restic!r}, [{actual_restic!r}, *args])
''',
        "systemctl": f'''import json, sys
from pathlib import Path
state = Path({str(state)!r})
values = json.loads(state.read_text())
action, name = sys.argv[1:3]
if action == "show":
    if os.environ.get("SYNTHETIC_FAIL") == "unit-metadata":
        print("LoadState=loaded\\nActiveState=failed")
        sys.exit(0)
    print("LoadState=loaded\\nActiveState=" + values[name])
else:
    with open({str(events)!r}, "a") as out:
        out.write(json.dumps([action, name]) + "\\n")
    if os.environ.get("SYNTHETIC_FAIL") == action:
        sys.exit(2)
    values[name] = "active" if action == "start" else "inactive"
    state.write_text(json.dumps(values))
'''.replace("import json, sys", "import json, sys, os")
    }
    for name, code in wrappers.items():
        tool = tools / name
        tool.write_text("#!" + os.sys.executable + "\n" + code)
        tool.chmod(0o700)
    command = ["bash", str(SCRIPT), "backup", "synthetic-discovery", "synthetic-kepler", INTERPRETER]
    readonly = ["bash", str(SCRIPT), "preflight", "synthetic-discovery", "synthetic-kepler", INTERPRETER]
    before = {str(p.relative_to(repository)): p.stat().st_mtime_ns for p in repository.rglob("*") if p.is_file()}
    for failure, phase in ((None, None), ("credential", "credential-preflight"),
                           ("snapshots", "repository-preflight"), ("supervisor", "supervisor-preflight"),
                           ("unknown", "remote-unobserved"), ("interpreter", "remote-unobserved"),
                           ("unit-metadata", "supervisor-preflight")):
        events.write_text("")
        environment["SYNTHETIC_FAIL"] = failure or ""
        result = subprocess.run(readonly, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert events.read_text() == "" and json.loads(state.read_text()) == initial, "preflight changed units"
        assert before == {str(p.relative_to(repository)): p.stat().st_mtime_ns for p in repository.rglob("*") if p.is_file()}, "preflight wrote repository"
        assert b"FAKE_SECRET" not in result.stdout + result.stderr
        assert b"PASS hermes-state-backup " not in result.stdout
        if phase is None:
            assert result.returncode == 0 and result.stdout == b"PASS hermes-state-preflight\n"
        else:
            assert result.returncode != 0
            value = json.loads(result.stderr.decode().split("BLOCKED hermes-state-backup ", 1)[1])
            assert value["phase"] == phase, (failure, value)
            assert value["class"] == ("PermissionError" if failure == "supervisor" else "ValueError" if failure == "unit-metadata" else "CalledProcessError")
            if failure == "credential":
                assert value["returncode"] == 23
            if failure == "interpreter":
                assert value["returncode"] == 127
    environment["SYNTHETIC_FAIL"] = "interpreter"
    failed_store = subprocess.run(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert failed_store.returncode != 0 and events.read_text() == ""
    assert json.loads(state.read_text()) == initial and b"PASS" not in failed_store.stdout
    assert b"FAKE_SECRET" not in failed_store.stdout + failed_store.stderr
    for failure in (None, "backup", "dump", "start", "interrupt", "timeout", "frame-negative", "frame-truncated", "frame-trailing"):
        state.write_text(json.dumps(initial))
        events.write_text("")
        environment["SYNTHETIC_FAIL"] = failure or ""
        result = subprocess.run(command, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=30)
        assert b"SYNTHETIC-PRIVATE-CONTENT" not in result.stdout + result.stderr
        records = [json.loads(line) for line in events.read_text().splitlines()]
        assert records[:6] == [["stop", name] for name in module.TIMERS + module.HEALTH + module.WRITERS], records
        assert records[-4:] == [["start", name] for name in module.WRITERS + module.TIMERS], records
        if failure != "start":
            assert json.loads(state.read_text()) == initial
        if result.returncode:
            assert b"PASS" not in result.stdout
        detail = json.loads(result.stderr.decode().split("BLOCKED hermes-state-backup ", 1)[1]) if result.returncode else {}
        assert (result.returncode == 0) == (failure is None), (failure, result.returncode, detail.get("phase"), detail.get("class"), "SSH relay lifecycle")
        if failure is None:
            snapshot = result.stdout.decode().strip().split("snapshot=")[1]
            valid = subprocess.run(["bash", str(SCRIPT), "rehearse", "synthetic-discovery", "synthetic-kepler", INTERPRETER, snapshot],
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert valid.returncode == 0
            assert len(events.read_text().splitlines()) == len(records), "rehearsal touched units"


def missing_restic():
    with tempfile.TemporaryDirectory(prefix="hermes-missing-restic-") as directory:
        tools = Path(directory)
        assert tools.parent == Path(tempfile.gettempdir()), "dependency fixture must honor TMPDIR"
        for name in ("bash", "sh", "tar", "just", "jq"):
            (tools / name).symlink_to(shutil.which(name))
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--without-dependency-control"],
                                env=dict(os.environ, PATH=str(tools)), stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=30)
        assert result.returncode != 0 and b"PASS hermes-state-backup-contract" not in result.stdout, "missing Restic falsely GREEN"
        assert b"PASS hermes-state-backup-encrypted-roundtrip" not in result.stdout


def framing(tmp):
    emitter = tmp / "synthetic-restic"
    emitter.write_text('import sys, json\n'
                       'sys.stdout.write(\'{"message_type":"status"}\\n\' * 100000)\n'
                       'sys.stdout.flush()\n'
                       'sys.stdin.buffer.read()\n'
                       'print(json.dumps({"message_type":"summary","snapshot_id":"' + 'a' * 64 + '"}))\n')
    for frame in (b"HERMES1 3\nabc\nHERMES1 END\n", b"HERMES1 -1\n", b"HERMES1 0\n", b"HERMES1 999999999999\n",
                  b"HERMES1 3\na", b"HERMES1 3\nabcBAD", b"X" * 41):
        reader, writer = os.pipe()
        os.write(writer, frame)
        os.close(writer)
        with os.fdopen(reader, "rb") as stream:
            if frame.startswith(b"HERMES1 3\nabc\nHERMES1 END"):
                assert module.frame_backup(stream, [sys.executable, str(emitter)], tmp) == "a" * 64
            else:
                rejects(lambda: module.frame_backup(stream, [sys.executable, str(emitter)], tmp))
    emitter.write_text(emitter.read_text().replace("100000", "1000000"))
    reader, writer = os.pipe()
    os.write(writer, b"HERMES1 3\nabc\nHERMES1 END\n")
    os.close(writer)
    with os.fdopen(reader, "rb") as stream:
        rejects(lambda: module.frame_backup(stream, [sys.executable, str(emitter)], tmp))
    assert (tmp / "backup-result").stat().st_size <= 16 * 1024**2


def diagnostics():
    private = "FAKE_SECRET /private/path command argv password"
    failed = subprocess.run(["bash", str(SCRIPT), "backup", "synthetic", "synthetic", private],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert failed.returncode != 0 and private.encode() not in failed.stderr
    assert b'"phase": "supervisor-preflight"' in failed.stderr, "failure phase absent"
    with patch.object(module, "PHASE", "credential-preflight", create=True):
        result = module.diagnostic(subprocess.CalledProcessError(23, [private], stderr=private))
    assert result == {"phase": "credential-preflight", "class": "CalledProcessError", "returncode": 23}
    with patch.object(module, "PHASE", "repository-preflight", create=True):
        result = module.diagnostic(PermissionError(private))
    assert result == {"phase": "repository-preflight", "class": "PermissionError"}
    assert private not in json.dumps(result)
    with patch.object(module, "PHASE", private):
        assert module.diagnostic(type("FAKE_SECRET", (Exception,), {})(private)) == {"phase": "remote-unobserved", "class": "OtherError"}


if __name__ == "__main__":
    if sys.argv[1:] == ["--red-missing-restic"]:
        missing_restic()
        sys.exit(0)
    if not shutil.which("restic"):
        print("BLOCKED hermes-state-backup: restic unavailable", file=sys.stderr)
        sys.exit(1)
    if sys.argv[1:] != ["--without-dependency-control"]:
        missing_restic()
    diagnostics()
    lifecycle()
    lifecycle(inactive=True)
    lifecycle(health_active=True)
    lifecycle(absent_timer=True)
    for recovery in ("writer-inactive", "timer-inactive", "get-failure", "unexpected"):
        lifecycle(recovery=recovery)
    lifecycle(inactive=True, recovery="inactive-active")
    lifecycle(absent_timer=True, recovery="timer-absence")
    lifecycle(failure="archive", recovery="get-failure")
    lifecycle(failure="verify", recovery="get-failure")
    readonly_modes()
    for failure in ("stop-timer", "stop-health", "stop-writer", "archive", "verify", "start-writer", "start-timer"):
        lifecycle(failure)
    with patch.object(module, "run") as external:
        rejects(lambda: module.local(str(SCRIPT), "rehearse", "fake", "fake", INTERPRETER, "latest"))
        external.assert_not_called()
    for output in (b"LoadState=loaded\nActiveState=activating\n", b"LoadState=not-found\nActiveState=inactive\n"):
        with patch.object(module, "run", return_value=subprocess.CompletedProcess([], 0, stdout=output)):
            rejects(module.states)
    with patch.object(module, "preflight", side_effect=ValueError("synthetic unavailable tool")), patch.object(module, "unit") as units:
        rejects(lambda: module.remote("backup"))
        units.assert_not_called()
    with tempfile.TemporaryDirectory(prefix="hermes-backup-validation-") as directory:
        tmp = Path(directory)
        assert tmp.parent == Path(tempfile.gettempdir()), "backup fixture must honor TMPDIR"
        framing(tmp)
        injected = tmp / "must-not-exist"
        invalid_recipe = subprocess.run(["just", "rehearse-discovery-hermes-kepler", '"; touch ' + str(injected) + '; #'],
                                        cwd=SCRIPT.parent.parent, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert invalid_recipe.returncode != 0 and not injected.exists()
        assert b"invalid snapshot ID" in invalid_recipe.stderr, invalid_recipe.stderr
        root, archive = archive_security(tmp)
        alias = tmp / "alias"
        alias.symlink_to(root, target_is_directory=True)
        with patch.object(module, "ROOT", alias):
            rejects(module.preflight)
        transport(tmp, root)
        encrypted(tmp, root, archive)
        for db in DATABASES:
            db.close()
    print("PASS hermes-state-backup-contract")
