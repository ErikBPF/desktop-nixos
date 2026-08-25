from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
KEPLER = (ROOT / "modules/hosts/kepler/default.nix").read_text()


def test_kepler_runs_three_k3s_workers_for_first_wave_headroom():
    assert "kepler.k3s.workerCount = 3;" in KEPLER
    assert "kepler.k3s.workerVcpu = 4;" in KEPLER
