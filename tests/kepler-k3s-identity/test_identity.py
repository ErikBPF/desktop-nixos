from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_stable_cluster_uses_homelab_identity_without_renaming_dns():
    module = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()
    justfile = ("\n".join(p.read_text() for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))]))

    assert 'clusterName = "homelab";' in module
    assert "k8s.${domain}" in module
    assert "rename context to 'homelab'" in justfile
    assert "sed 's/: default$/: homelab/'" in justfile
    assert "~/.kube/homelab-lan.yaml" in justfile
    assert "kubectl --context homelab -n argocd" in justfile
