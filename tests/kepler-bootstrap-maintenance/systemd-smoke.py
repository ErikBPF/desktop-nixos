"""Exercise evaluated dependency semantics using disposable user units only."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def ctl(*args):
    return subprocess.run(["systemctl", "--user", *args], capture_output=True,
                          text=True, timeout=15)


def wait_for(predicate):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    assert predicate(), "expected disposable systemd transition did not occur"


def main():
    fixture = json.loads(subprocess.check_output(
        ["nix", "eval", "--offline", "--impure", "--json", "--file",
         "tests/kepler-bootstrap-maintenance/fixture.nix"], cwd=ROOT, timeout=90))
    assert ctl("show-environment").returncode == 0, "user systemd bus required"
    with tempfile.TemporaryDirectory(prefix="bootstrap-maintenance-") as directory:
        path = Path(directory)
        prefix = "bootstrap-maintenance-" + uuid.uuid4().hex
        guest, reconcile = prefix + "-guest.service", prefix + "-reconcile.service"
        timer = prefix + "-reconcile.timer"
        count = path / "reconciled"
        script = path / "reconcile"
        script.write_text(f"#!{shutil.which('sh')}\necho reconciled >> {count}\n")
        script.chmod(0o700)
        (path / guest).write_text(
            "[Service]\nType=simple\n" + f"ExecStart={shutil.which('sleep')} infinity\n")
        condition = fixture["condition"]
        if condition:
            condition = condition.replace("/bin/systemctl ", "/bin/systemctl --user ").replace("k3s.service", guest)
        (path / reconcile).write_text(
            "[Unit]\n" + (f"After={guest}\n" if "k3s.service" in fixture["after"] else "")
            + (f"Wants={guest}\n" if "k3s.service" in fixture["wants"] else "")
            + "[Service]\nType=oneshot\n"
            + (f"ExecCondition={condition}\n" if condition else "")
            + f"ExecStart={script}\n")
        (path / timer).write_text(
            f"[Timer]\nOnActiveSec=1s\nOnUnitActiveSec=1s\nAccuracySec=100ms\nUnit={reconcile}\n")
        def runs():
            return len(count.read_text().splitlines()) if count.exists() else 0
        try:
            result = ctl("link", *(str(path / unit) for unit in (guest, reconcile, timer)))
            assert result.returncode == 0, result.stderr
            assert ctl("daemon-reload").returncode == 0
            assert ctl("start", guest, reconcile).returncode == 0
            assert runs() == 1, "healthy boot reconciliation must run"
            assert ctl("start", timer).returncode == 0
            wait_for(lambda: runs() >= 2)
            # Avoid a racing in-flight reconciliation before the maintenance stop.
            assert ctl("stop", timer, reconcile, guest).returncode == 0
            before = runs()
            assert ctl("start", timer).returncode == 0
            time.sleep(3)
            assert ctl("is-active", guest).stdout.strip() == "inactive", (
                "credential timer resurrected operator-stopped K3s")
            assert runs() == before, "inactive K3s must skip credential writes"
            assert ctl("is-failed", reconcile).stdout.strip() != "failed", (
                "inactive K3s must skip rather than fail reconciliation")
            assert ctl("start", guest).returncode == 0
            wait_for(lambda: runs() > before)
            assert runs() > before, "timer must resume reconciliation after healthy restart"
            print("KEPLER_BOOTSTRAP_MAINTENANCE_SYSTEMD_OK")
        finally:
            ctl("stop", timer, reconcile, guest)
            ctl("disable", timer, reconcile, guest)
            ctl("reset-failed", timer, reconcile, guest)
            ctl("daemon-reload")


if __name__ == "__main__":
    main()
