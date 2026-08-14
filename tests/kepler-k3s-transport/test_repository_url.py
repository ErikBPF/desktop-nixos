from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_argocd_repository_uses_github_ssh_port_443():
    module = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()

    assert (
        "--from-literal=url=ssh://git@ssh.github.com:443/"
        "ErikBPF/homelab-gitops.git"
    ) in module
