from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys

import pytest


JUSTFILE = Path(__file__).parents[2] / "justfile"

def justfile_text():
    return "\n".join(p.read_text() for p in [JUSTFILE, *sorted((JUSTFILE.parent / "just").glob("*.just"))])


def run_recipe(tmp_path, arguments, env=None):
    shutil.copy2(JUSTFILE, tmp_path / "justfile")
    shutil.copytree(JUSTFILE.parent / "just", tmp_path / "just")
    shutil.copy2(JUSTFILE.parent / "fleet.json", tmp_path / "fleet.json")
    mock_bin = tmp_path / "bin"
    mock_bin.mkdir(exist_ok=True)
    activation = tmp_path / "activation"
    activation.mkdir(exist_ok=True)
    activate = activation / "activate"
    activate.write_text("#!/usr/bin/env bash\nexit 0\n")
    activate.chmod(0o755)
    graph = tmp_path / "disko-script"
    graph.write_text("for dev in /dev/disk/by-id/nvme-Force_MP510_19458242000129183963;\n")
    nix = mock_bin / "nix"
    nix.write_text(
        f"#!{sys.executable}\n"
        "import json, sys\n"
        "from pathlib import Path\n"
        "with Path('calls.jsonl').open('a') as calls:\n"
        "    calls.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        f"if any('home.activationPackage' in arg for arg in sys.argv): print({str(activation)!r})\n"
        f"if any(arg.endswith('.diskoScript') for arg in sys.argv): print({str(graph)!r})\n"
        "sys.exit(0)\n"
    )
    nix.chmod(0o755)
    shutil.copy2(nix, mock_bin / "nixos-rebuild")
    sudo = mock_bin / "sudo"
    sudo.write_text('#!/usr/bin/env bash\nexec "$@"\n')
    sudo.chmod(0o755)
    # `switch`/`boot`/`home-switch` refuse a target that is not the local host,
    # so the sandbox reports the harness hostname. Override with
    # HOSTNAME_UNDER_TEST to exercise the foreign-host path.
    hostname = mock_bin / "hostname"
    hostname.write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "${HOSTNAME_UNDER_TEST:-endeavour}"\n'
    )
    hostname.chmod(0o755)
    for name in ("ssh", "scp", "systemd-run"):
        transport = mock_bin / name
        transport.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "from pathlib import Path\n"
            "with Path('transport.jsonl').open('a') as calls:\n"
            "    calls.write(json.dumps(sys.argv) + '\\n')\n"
        )
        transport.chmod(0o755)
    result = subprocess.run(
        ["just", "--no-dotenv", *arguments], cwd=tmp_path,
        env=os.environ | {"PATH": f"{mock_bin}:{os.environ['PATH']}", "HOME": str(tmp_path)} | (env or {}),
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in (tmp_path / "calls.jsonl").read_text().splitlines()]


@pytest.mark.parametrize("target,expected", [
    ("orion", "ORION_OVERRIDE"),
    ("apollo", "ORION_OVERRIDE"),
    ("endeavour", "ORION_OVERRIDE"),
])
def test_cli_builder_overrides_survive_child_just(tmp_path, target, expected):
    calls = run_recipe(tmp_path, [
        "orion_builder=ORION_OVERRIDE", "build", target,
    ])
    assert calls[0][calls[0].index("--builders") + 1] == expected
    assert calls[0][calls[0].index("--max-jobs") + 1] == "0"


@pytest.mark.parametrize("overrides", [[], ["orion_builder=ORION_OVERRIDE"]])
def test_orion_graph_proof_uses_orion_only(tmp_path, overrides):
    call = run_recipe(tmp_path, [*overrides, "orion-esp-graph-proof"])[0]
    assert "--builders" in call
    builders = call[call.index("--builders") + 1]
    if overrides:
        assert builders == "ORION_OVERRIDE"
    else:
        assert builders.startswith("ssh-ng://erik@orion-builder:2222 ")
        assert "apollo-builder" not in builders
    assert "--max-jobs" in call
    assert call[call.index("--max-jobs") + 1] == "0"
    assert "--builders-use-substitutes" in call


def test_orion_migration_exports_pool_before_nested_proofs():
    body = recipe("deploy-orion-esp")
    export = body.index('export NIX_CONFIG="builders = {{orion_builder}}')
    assert export < body.index("just orion-esp-live-preflight")
    assert export < body.index("just orion-esp-graph-proof")


@pytest.mark.parametrize("name", ["switch-voyager", "switch-vanguard", "boot-vanguard"])
@pytest.mark.parametrize("overrides", [[], ["orion_builder=ORION_OVERRIDE"]])
def test_x86_bootstrap_helpers_use_orion_only(tmp_path, name, overrides):
    call = run_recipe(tmp_path, [*overrides, name])[0]
    builders = call[call.index("builders") + 1]
    if overrides:
        assert builders == "ORION_OVERRIDE"
    else:
        assert "orion-builder:2222" in builders
        assert "apollo-builder:2222" not in builders
    assert call[call.index("--max-jobs") + 1] == "0"
    transports = [json.loads(line) for line in (tmp_path / "transport.jsonl").read_text().splitlines()]
    assert [Path(call[0]).name for call in transports] == ["ssh", "scp", "ssh"]
    assert not (tmp_path / ".config/sops/age/keys.txt").exists()


@pytest.mark.parametrize("arguments", [
    ["switch", "endeavour"], ["boot", "endeavour"], ["dry", "endeavour"],
    ["home-switch", "endeavour"], ["deploy", "endeavour", "192.0.2.10"],
    ["deploy-boot", "endeavour", "192.0.2.10"],
])
def test_ordinary_recipes_offer_orion_without_local_fallback(tmp_path, arguments):
    calls = run_recipe(tmp_path, arguments)
    call = calls[0]
    assert call[call.index("--max-jobs") + 1] == "0"
    assert any("orion-builder:2222" in arg for arg in call)
    assert not any("apollo-builder:2222" in arg for arg in call)


@pytest.mark.parametrize("name", ["deploy-rs", "deploy-rs-preview", "deploy-rs-boot"])
def test_deploy_rs_realizes_tool_and_closure_through_same_pool(tmp_path, name):
    call = run_recipe(tmp_path, [name, "orion"])[0]
    outer, inner = call[:call.index("--")], call[call.index("--") + 1:]
    assert outer[outer.index("--max-jobs") + 1] == "0"
    assert "--builders-use-substitutes" in outer
    assert outer[outer.index("--builders") + 1].startswith("ssh-ng://erik@orion-builder:2222 ")
    assert inner[inner.index("--max-jobs") + 1] == "0"
    assert inner[inner.index("builders") + 1] == outer[outer.index("--builders") + 1]
    if name == "deploy-rs-preview":
        assert "--skip-checks --dry-activate" in " ".join(inner)


def test_sd_image_reuses_canonical_orion_endpoint_and_personal_client_key(tmp_path):
    call = run_recipe(tmp_path, ["build-archinaut-sd"])[0]
    builders = call[call.index("--builders") + 1]
    assert builders.startswith("ssh-ng://erik@orion-builder:2222 ")
    assert "aarch64-linux" in builders
    assert "/home/erik/.ssh/id_ed25519" in builders
    assert call[call.index("--max-jobs") + 1] == "0"


def test_no_recipe_permits_a_local_build():
    text = justfile_text()
    assert "--max-jobs 1" not in text
    assert "max-jobs = 1" not in text
    assert "apollo_builder" not in text
    assert "kepler_builder" not in text


def test_builder_invocations_forbid_local_jobs():
    # Every --builders invocation must carry --max-jobs 0, or sit in a
    # NIX_CONFIG block that sets max-jobs = 0.
    lines = justfile_text().splitlines()
    for index, line in enumerate(lines):
        if ("--builders" in line or "--option builders" in line) and "--max-jobs 0" not in line:
            window = "\n".join(lines[index:index + 4])
            assert "--max-jobs 0" in window, line
        if 'NIX_CONFIG="builders' in line:
            window = "\n".join(lines[index:index + 4])
            assert "max-jobs = 0" in window, line


def test_hermes_sandbox_validation_remains_orion_only(tmp_path):
    call = run_recipe(tmp_path, [
        "orion_builder=ORION_OVERRIDE",
        "validate-hermes-orion",
    ])[0]
    assert call[call.index("--builders") + 1] == "ORION_OVERRIDE"
    assert call[call.index("--max-jobs") + 1] == "0"
    assert {arg for arg in call if arg.startswith(".#checks.")} == {
        ".#checks.x86_64-linux.hermes-plugin-selftests",
        ".#checks.x86_64-linux.hermes-plugin-native",
        ".#checks.x86_64-linux.hermes-state-backup",
    }


def test_no_guest_kace_uninstall_or_obsolete_host_watchdog_actions():
    text = justfile_text()
    assert "remove-ubuntu-work-kace" not in text
    assert "ampagent" not in text
    assert "KACE stays" not in text
    assert "proprietary KACE" not in text
    assert "endeavour)" not in recipe("grafana-alert-retry")


def test_remote_checks_include_endeavour_without_host_locality_exception():
    body = recipe("check-remote")
    assert 'found_endeavour=true' in body
    assert 'found_endeavour=true\n        continue' not in body
    assert '--max-jobs 0' in body
    assert 'just check-remote' in recipe("check-endeavour-remote")


@pytest.mark.parametrize("name,selector", [
    ("provision", "{{host}}"), ("nixos-anywhere", "{{target}}"),
    ("deploy-orion", "orion"), ("deploy-discovery", "discovery"),
    ("deploy-kepler", "kepler"), ("deploy-pathfinder-esp", "pathfinder"),
    ("deploy-endeavour", "endeavour"),
])
def test_installers_propagate_target_aware_pool_to_tool_and_build(name, selector):
    body = recipe(name)
    assert f'export NIX_CONFIG="builders = $(just _builders {selector})' in body
    assert 'max-jobs = 0' in body
    assert 'builders-use-substitutes = true' in body


def recipe(name: str) -> str:
    text = justfile_text()
    match = re.search(
        rf"^{re.escape(name)}(?: [^\n:]*)?:\n(?P<body>(?:^[ \t]+.*\n|^\n)*)",
        text,
        re.MULTILINE,
    )
    assert match, f"missing {name} recipe"
    return match.group("body")


def test_build_only_realizes_toplevel_without_activation():
    body = recipe("build")
    assert "nix build --no-link" in body
    assert ".#nixosConfigurations.{{target}}.config.system.build.toplevel" in body
    assert "nixos-rebuild" not in body
    assert " switch " not in body


def test_switch_keeps_explicit_local_activation_path():
    body = recipe("switch")
    assert "nixos-rebuild switch --flake .#{{target}}" in body
    assert 'BUILDERS="$(just _builders {{target}})"' in body
    assert "builders-use-substitutes true" in body


def test_builder_preflight_is_explicit_and_target_aware():
    body = recipe("builder-preflight")
    assert 'BUILDERS="$(just _builders {{target}})"' in body
    assert 'sudo ./scripts/builder-preflight.sh "$BUILDERS"' in body
    assert "builder-preflight" not in recipe("build")
    assert "builder-preflight" not in recipe("switch")


def test_deploy_rs_forbids_local_jobs():
    body = recipe("deploy-rs")
    assert "--max-jobs 0" in body


def test_dry_all_builds_fleet_in_one_scheduler_invocation():
    body = recipe("dry-all")
    assert "just build-all" in body
    assert "nixos-rebuild" not in body


def test_home_switch_is_independent_and_uses_normal_xdg_roots(tmp_path):
    run_recipe(tmp_path, ["home-switch", "endeavour"], env={
        "XDG_CONFIG_HOME": "/isolated/config",
        "XDG_DATA_HOME": "/isolated/data",
        "XDG_STATE_HOME": "/isolated/state",
        "XDG_CACHE_HOME": "/isolated/cache",
    })
    transport = tmp_path / "transport.jsonl"
    assert transport.exists(), "activation must run outside the calling backend service"
    call = json.loads(transport.read_text().splitlines()[-1])
    assert Path(call[0]).name == "systemd-run"
    assert "--user" in call and "--wait" in call and "--collect" in call
    assert "--pipe" not in call and "--scope" not in call
    assert "--unit=home-manager-switch" in call
    for variable, suffix in {
        "XDG_CONFIG_HOME": ".config", "XDG_DATA_HOME": ".local/share",
        "XDG_STATE_HOME": ".local/state", "XDG_CACHE_HOME": ".cache",
    }.items():
        assert f"--setenv={variable}={tmp_path / suffix}" in call
    assert "--setenv=HOME_MANAGER_BACKUP_EXT=backup" in call
    assert call[-1] == str(tmp_path / "activation/activate")
