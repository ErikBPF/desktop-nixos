"""Real user-systemd ordering; fake hypervisor/etcd, no production operations."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path


def ctl(*args):
    result = subprocess.run(["systemctl", "--user", *args], capture_output=True,
                            text=True, timeout=20, check=False)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture")
    parser.add_argument("--old-installer", action="store_true")
    args = parser.parse_args()
    fixture = json.loads(Path(args.fixture).read_text())
    assert fixture["baselineSystem"] == "/nix/store/zi7mrrickfv7haaglmy7yrsljr9zgk9p-nixos-system-kepler-26.11.20261115.5c3cda7"
    assert fixture["restartIfChanged"] is False
    assert fixture["baseline"]["clusterInit"] is True
    assert fixture["baseline"]["serverAddr"] == ""
    assert "multi-user.target" in fixture["baseline"]["k3sWantedBy"]
    assert fixture["candidate"]["k3sWantedBy"] == []
    assert fixture["candidate"]["clusterInit"] is False
    assert fixture["candidate"]["serverAddr"] == "https://10.250.0.13:6443"
    assert ctl("show-environment").returncode == 0, "user systemd bus required"
    with tempfile.TemporaryDirectory(prefix="cp1-boot-order-") as directory:
        root = Path(directory)
        prefix = "cp1-boot-order-" + uuid.uuid4().hex
        install, vm, host = (prefix + suffix for suffix in
                             ("-installer.service", "-vm.service", "-host.target"))
        units = [install, vm, host]
        marker = root / "unsafe-start"
        sleep = shutil.which("sleep")
        shell = shutil.which("sh")
        systemctl = shutil.which("systemctl")
        for label in ("baseline", "candidate"):
            runner = root / label
            runner.mkdir()
            boot = prefix + "-" + label + ".target"
            k3s = prefix + "-" + label + "-k3s.service"
            units.extend((boot, k3s))
            # Translate only the evaluated guest boot edge into an isolated target.
            (root / boot).write_text("[Unit]\n" + (
                f"Wants={k3s}\nAfter={k3s}\n" if fixture[label]["k3sWantedBy"] else ""))
            (root / k3s).write_text("[Service]\nType=oneshot\nRemainAfterExit=yes\n"
                                    f"ExecStart={shell} -c 'echo attempted >> {marker}'\n")
            script = runner / "run"
            script.write_text(f"#!{shell}\n{systemctl} --user start {boot}\nexec {sleep} infinity\n")
            script.chmod(0o700)
        # Simulate a staged current pin and a still-running old guest provenance.
        (root / "current").symlink_to(root / "candidate")
        (root / "booted").symlink_to(root / "baseline")
        selected = fixture["baseline" if args.old_installer else "candidate"]
        assert "microvm@cp-1.service" in selected["before"]
        assert "microvm@cp-1.service" in selected["partOf"]
        assert "microvms.target" in selected["wantedBy"]
        match = re.search(r"ln -sTf (\S+) current", selected["installer"])
        assert match and match[1] == selected["runner"]
        label = "baseline" if selected["runner"] == fixture["baseline"]["runner"] else "candidate"
        (root / install).write_text(
            f"[Unit]\nBefore={vm}\nPartOf={vm}\n[Service]\nType=oneshot\n"
            f"RemainAfterExit={'yes' if selected['remainAfterExit'] else 'no'}\n"
            f"WorkingDirectory={root}\nExecStart={shutil.which('ln')} -sTf {root / label} current\n")
        (root / vm).write_text(f"[Service]\nType=simple\nExecStart={root / 'current/run'}\n")
        (root / host).write_text(f"[Unit]\nWants={install} {vm}\nAfter={install} {vm}\n")
        try:
            result = ctl("link", *(str(root / unit) for unit in units))
            assert result.returncode == 0, result.stderr
            assert ctl("daemon-reload").returncode == 0
            # Failure before membership mutation: installer alone must not boot guest.
            assert ctl("start", install).returncode == 0
            assert not marker.exists()
            assert ctl("is-active", vm).stdout.strip() == "inactive"
            assert (root / "booted").resolve() == root / "baseline"
            # Two fresh host transactions model reboot/retry after a failed operation.
            for _ in range(2):
                assert ctl("start", host).returncode == 0
                # Wait for the fake hypervisor to enter the guest boot target.
                boot = prefix + "-" + label + ".target"
                for attempt in range(100):
                    if ctl("is-active", boot).stdout.strip() == "active":
                        break
                    time.sleep(0.02)
                assert ctl("is-active", boot).stdout.strip() == "active"
                assert (root / "current").resolve() == root / "candidate", "old installer restored unsafe boot runner"
                assert not marker.exists(), "missing-etcd guest boot attempted K3s"
                assert ctl("stop", *units).returncode == 0
            print("CP1_DURABLE_BOOT_ORDER_SYSTEMD_OK (hypervisor/etcd simulated)")
        finally:
            ctl("stop", *units)
            ctl("disable", *units)
            ctl("reset-failed", *units)
            ctl("daemon-reload")


if __name__ == "__main__":
    main()
