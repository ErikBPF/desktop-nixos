"""Disposable local user-systemd proof; never touches host or guest units."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def systemctl(*args):
    return subprocess.run(
        ["systemctl", "--user", *args], capture_output=True, text=True, timeout=15
    )


def wait_for(predicate):
    end = time.monotonic() + 8
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.1)
    assert predicate(), "guest did not recover after the reader became ready"


def main():
    assert systemctl("show-environment").returncode == 0, "local user bus required"
    wants = json.loads(subprocess.check_output(
        ["nix", "eval", "--offline", "--json",
         ".#nixosConfigurations.kepler.config.systemd.services.harbor-reader.wants"],
        cwd=ROOT, text=True, timeout=90,
    ))
    reverse = "microvm@cp-1.service" in wants
    with tempfile.TemporaryDirectory(prefix="kepler-reader-fixture-") as directory:
        path = Path(directory)
        prefix = "kepler-reader-fixture-" + uuid.uuid4().hex
        reader, guest = prefix + "-reader.service", prefix + "-guest.service"
        (path / reader).write_text(
            "[Unit]\nStartLimitIntervalSec=0\n"
            + (f"Wants={guest}\n" if reverse else "")
            + "[Service]\nType=simple\nRestart=on-failure\nRestartSec=1\n"
            + f"ExecStart={shutil.which('sleep')} infinity\n"
            + f"ExecStartPost={shutil.which('test')} -f {path}/ready\n"
        )
        (path / guest).write_text(
            f"[Unit]\nRequires={reader}\nAfter={reader}\n"
            "[Service]\nType=oneshot\nRemainAfterExit=yes\n"
            f"ExecStart={shutil.which('touch')} {path}/started\n"
        )
        try:
            linked = systemctl("link", str(path / reader), str(path / guest))
            assert linked.returncode == 0, linked.stderr
            assert systemctl("daemon-reload").returncode == 0
            initial = systemctl("start", guest)
            assert initial.returncode != 0, "unready reader must block guest startup"
            assert not (path / "started").exists(), "credential gate bypassed"
            (path / "ready").touch()
            wait_for(lambda: (path / "started").exists())
            assert systemctl("is-active", reader).stdout.strip() == "active"
            assert systemctl("stop", guest).returncode == 0
            time.sleep(2)
            assert systemctl("is-active", guest).stdout.strip() == "inactive", (
                "healthy reader must not undo an explicit guest stop"
            )
            assert systemctl("is-active", reader).stdout.strip() == "active"
            print("KEPLER_READER_SYSTEMD_RECOVERY_OK")
        finally:
            systemctl("stop", guest, reader)
            systemctl("disable", guest, reader)
            systemctl("reset-failed", guest, reader)
            systemctl("daemon-reload")


if __name__ == "__main__":
    main()
