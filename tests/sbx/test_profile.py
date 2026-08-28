from pathlib import Path

import yaml


ROOT = Path(__file__).parents[2]


def test_sbx_package_is_pinned_and_runnable():
    module = (ROOT / "modules/packages/sbx.nix").read_text()

    assert 'packages.sbx' in module
    assert 'version = "0.39.0";' in module
    assert "github.com/docker/sbx-releases/releases/download" in module
    assert 'hash = "sha256-LsRbx5OMIML0Bv6MxyKUrVqVS9wEdgFIS4m/GhCDEdQ=";' in module
    assert 'allowUnfreePredicate = pkg: lib.getName pkg == "docker-sbx";' in module
    assert 'system == "x86_64-linux"' in module
    assert "pkgs.autoPatchelfHook" in module
    assert "pkgs.e2fsprogs" in module


def test_repo_profile_uses_an_isolated_clone_with_bounded_resources():
    profile = yaml.safe_load((ROOT / ".sbxenv.yaml").read_text())

    assert profile == {
        "schemaVersion": "1",
        "name": "desktop-nixos-codex",
        "agent": "codex",
        "workspace": {"path": ".", "clone": True},
        "sandboxOptions": {"cpus": 4, "memory": "8g"},
    }
