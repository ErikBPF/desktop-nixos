from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_voyager_has_a_distinct_sops_recipient():
    config = (ROOT / ".sops.yaml").read_text()
    trend_rule, secrets_rule = config.split(
        "  - path_regex: secrets/sops/secrets.yaml$", maxsplit=1
    )

    assert "&voyager age12g3sullwtjugy3f02cc4v5m6yt45qz9vt2muck2dnu9pqrfdmurs8jtu5s" in config
    assert "          - *voyager" not in trend_rule
    assert "          - *voyager" in secrets_rule


def test_voyager_relay_is_enabled():
    host = (ROOT / "modules/hosts/voyager/default.nix").read_text()

    assert "services.netbirdRelay.enable = true;" in host


def test_voyager_uses_its_reserved_public_ip():
    meta = (ROOT / "modules/meta.nix").read_text()

    assert 'ip = "163.176.78.19";' in meta
