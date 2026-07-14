import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "builder-preflight.sh"


def run_preflight(tmp_path, builders):
    calls = tmp_path / "calls"
    calls.unlink(missing_ok=True)
    mock_bin = tmp_path / "bin"
    mock_bin.mkdir(exist_ok=True)
    timeout = mock_bin / "timeout"
    timeout.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' \"$*\" >> \"$PREFLIGHT_CALLS\"\n"
        "case \"$*\" in *192.0.2.20*) exit 1;; esac\n"
    )
    timeout.chmod(0o755)
    env = os.environ | {
        "PATH": f"{mock_bin}:{os.environ['PATH']}",
        "PREFLIGHT_CALLS": str(calls),
    }
    result = subprocess.run(
        [str(SCRIPT), builders], capture_output=True, text=True, env=env
    )
    return result, calls.read_text() if calls.exists() else ""


def test_pings_each_builder_with_explicit_port_and_key(tmp_path):
    builders = (
        "ssh-ng://erik@192.0.2.10:2222 x86_64-linux /root/.ssh/nix-builder 16 2 kvm"
        " ; ssh-ng://erik@192.0.2.11:2222 x86_64-linux /root/.ssh/nix-builder 2 1 -"
    )
    result, calls = run_preflight(tmp_path, builders)

    assert result.returncode == 0, result.stderr
    assert calls.count("nix store ping --store") == 2
    assert "ssh-ng://erik@192.0.2.10:2222?ssh-key=/root/.ssh/nix-builder" in calls
    assert "OK 192.0.2.10:2222" in result.stdout
    assert "OK 192.0.2.11:2222" in result.stdout


def test_rejects_builder_without_explicit_port_before_connecting(tmp_path):
    result, calls = run_preflight(
        tmp_path,
        "ssh-ng://erik@192.0.2.10 x86_64-linux /root/.ssh/nix-builder 1 1 -",
    )

    assert result.returncode != 0
    assert calls == ""
    assert "explicit port required" in result.stderr


def test_checks_all_builders_and_reports_failed_endpoint(tmp_path):
    builders = (
        "ssh-ng://erik@192.0.2.20:2222 x86_64-linux /root/.ssh/nix-builder 1 1 -"
        " ; ssh-ng://erik@192.0.2.21:2222 x86_64-linux /root/.ssh/nix-builder 1 1 -"
    )
    result, calls = run_preflight(tmp_path, builders)

    assert result.returncode != 0
    assert calls.count("nix store ping --store") == 2
    assert "FAIL 192.0.2.20:2222" in result.stderr
    assert "check SSH, builder key, and nix-daemon" in result.stderr
    assert "OK 192.0.2.21:2222" in result.stdout


def test_rejects_empty_or_unsupported_builder_input(tmp_path):
    empty, _ = run_preflight(tmp_path, "")
    unsupported, calls = run_preflight(
        tmp_path, "ssh://erik@192.0.2.10:2222 x86_64-linux - 1 1 -"
    )

    assert empty.returncode != 0
    assert "usage:" in empty.stderr
    assert unsupported.returncode != 0
    assert "expected ssh-ng://" in unsupported.stderr
    assert calls == ""
