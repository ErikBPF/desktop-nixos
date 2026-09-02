from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_discovery_renders_scoped_cognee_signing_material() -> None:
    source = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()

    assert 'secret \\"secret/data/home/cognee-signing\\"' in source
    assert 'destination = "/run/vault-agent/cognee-cosign.key"' in source
    assert 'destination = "/run/vault-agent/cognee-cosign.password"' in source
    assert 'secret \\"secret/data/home/cognee-harbor-publisher\\"' in source
    assert 'destination = "/run/vault-agent/cognee-harbor-publisher.env"' in source
    assert ".Data.data.COSIGN_PRIVATE_KEY" in source
    assert ".Data.data.COSIGN_PASSWORD" in source


def test_signing_bootstrap_uses_stdin_and_exact_vault_path() -> None:
    source = (ROOT / "justfile").read_text()

    assert "bootstrap-cognee-signing private_key password_file:" in source
    assert "secret/home/cognee-signing" in source
    assert "@/dev/stdin" in source
    assert "COSIGN_PRIVATE_KEY" in source
    assert "COSIGN_PASSWORD" in source
