import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_orion_keeps_audit_enabled_without_losing_jovian_gpu_params():
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            ".#nixosConfigurations.orion.config.boot.kernelParams",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    params = json.loads(result.stdout)

    assert "audit=1" in params
    assert "audit=0" not in params
    assert "amdgpu.lockup_timeout=5000,10000,10000,5000" in params
    assert "ttm.pages_min=2097152" in params
    assert "amdgpu.sched_hw_submission=4" in params
