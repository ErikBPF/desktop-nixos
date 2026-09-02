from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_discovery_renders_scoped_cognee_signing_material() -> None:
    source = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()

    assert 'secret \\"secret/data/home/cognee-signing\\"' in source
    assert 'destination = "/run/vault-agent/cognee-cosign.key"' in source
    assert 'destination = "/run/vault-agent/cognee-cosign.password"' in source
    assert ".Data.data.COSIGN_PRIVATE_KEY" in source
    assert ".Data.data.COSIGN_PASSWORD" in source
