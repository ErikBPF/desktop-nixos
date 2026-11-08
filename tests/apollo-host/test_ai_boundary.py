import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def test_apollo_serving_disables_inherited_development_controls(tmp_path):
    source = (ROOT / "modules/hosts/apollo/default.nix").read_text()
    script = source.split('serveVllm = pkgs.writeShellScript "serve-vllm.sh" \'\'', 1)[1].split("'';", 1)[0]
    fake_vllm = tmp_path / "vllm"
    fake_vllm.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "print(json.dumps({'dev': os.getenv('VLLM_SERVER_DEV_MODE'), 'args': sys.argv[1:]}))\n"
    )
    fake_vllm.chmod(0o755)
    result = subprocess.run(
        [shutil.which("bash"), "-c", script],
        env={"PATH": f"{tmp_path}:{os.defpath}", "VLLM_SERVER_DEV_MODE": "1"},
        capture_output=True,
        text=True,
        check=True,
    )
    served = json.loads(result.stdout)
    assert served["dev"] != "1", "inherited development controls must be disabled"
    assert served["args"][:2] == ["serve", "/model"]
    assert "qwen38-27b-nvfp4" in served["args"]
    assert "--profiler-config" not in served["args"]
    assert "--tool-server" not in served["args"]


def test_apollo_serving_preserves_container_and_preflight_boundaries():
    source = (ROOT / "modules/hosts/apollo/default.nix").read_text()
    for boundary in (
        '"--user"\n            "1000:100"',
        '"--security-opt=no-new-privileges"',
        '"nvidia.com/gpu=all"',
        '"${apolloAiModel}:/model:ro"',
        '"/mnt/data/ai/cache:/cache"',
        '"${apolloAiRuntime}:/trial:ro"',
        'chain_rules=$(iptables -S apollo-qwen-litellm)',
        '-A apollo-qwen-litellm -j REJECT --reject-with icmp-port-unreachable',
        '"${apolloAiPreflight}"',
    ):
        assert boundary in source, boundary
