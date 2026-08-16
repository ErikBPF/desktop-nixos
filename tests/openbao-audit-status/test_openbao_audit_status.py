from pathlib import Path


JUSTFILE = (Path(__file__).parents[2] / "justfile").read_text()


def test_audit_status_never_prints_token_or_payloads():
    recipe = JUSTFILE.split("openbao-audit-status:", 1)[1].split("\n\n", 1)[0]

    assert "/v1/sys/audit" in recipe
    assert "vault_root_token" in recipe
    assert "file_path" in recipe
    assert "log_raw" in recipe
    assert "request" not in recipe
    assert "response" not in recipe


def test_eso_contract_reports_only_policy_and_role_metadata():
    recipe = JUSTFILE.split("openbao-eso-contract:", 1)[1].split("\n\n", 1)[0]

    assert "/v1/auth/approle/role/eso" in recipe
    assert "/v1/sys/policies/acl/eso" in recipe
    assert "token_policies" in recipe
    assert "token_ttl" in recipe
    assert "token_max_ttl" in recipe
    assert "/secret-id" not in recipe
    assert ".data.secret_id" not in recipe
