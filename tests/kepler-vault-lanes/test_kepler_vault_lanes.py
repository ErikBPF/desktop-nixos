from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()
JUSTFILE = (ROOT / "justfile").read_text()


def test_cp1_reconciles_role_and_secret_ids_for_each_lane():
    assert 'vaultLanes = ["platform" "homelab" "home-services"]' in MODULE
    assert '"vault-approle-$lane"' in MODULE
    assert "vault_approle_''${lane}_role_id" in MODULE
    assert "vault_approle_''${lane}_secret_id" in MODULE
    assert "--from-file=role_id=" in MODULE
    assert "--from-file=secret_id=" in MODULE


def test_capture_recipe_mints_only_declared_lane_roles_into_sops():
    recipe = JUSTFILE.split("capture-k3s-vault-lane-secrets:", 1)[1].split("\n\n", 1)[0]
    assert 'for lane in platform homelab home-services' in recipe
    assert 'role/eso-$lane/role-id' in recipe
    assert 'role/eso-$lane/secret-id' in recipe
    assert '["k3s_bootstrap"]' in recipe
