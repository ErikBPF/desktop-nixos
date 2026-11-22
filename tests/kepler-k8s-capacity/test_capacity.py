from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
KEPLER = (ROOT / "modules/hosts/kepler/default.nix").read_text()
K3S_CLUSTER = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()


def test_kepler_runs_three_k3s_workers_for_first_wave_headroom():
    assert "kepler.k3s.workerCount = 3;" in KEPLER
    assert "kepler.k3s.workerVcpu = 4;" in KEPLER
    assert "kepler.k3s.workerMem = 10240;" in KEPLER
    assert "mem = 3072;" in K3S_CLUSTER
