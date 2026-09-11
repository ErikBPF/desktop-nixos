from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_work_litellm_provider_uses_sops_token():
    opencode = (ROOT / "modules/dev/opencode.nix").read_text()
    client = (ROOT / "modules/services/opencode-client.nix").read_text()
    secrets = (ROOT / "secrets/sops/secrets.yaml").read_text()

    assert 'export OPENCODE_WORK_KEY="$(</run/secrets/opencode/work_key)"' in opencode
    assert 'baseURL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1";' in opencode
    assert 'apiKey = "{env:OPENCODE_WORK_KEY}";' in opencode
    assert 'resource = "work";' in opencode
    work = opencode.split("        work = {", 1)[1].split("        opencode = {", 1)[0]
    for model in ("chatgpt-5.6-luna", "chatgpt-5.6-sol", "chatgpt-5.6-terra",
                  "deepseek-v4.1-flash", "glm-5.3-flash"):
        assert f'"{model}" = {{' in work
    assert work.count('options.reasoningEffort = "none";') == 3
    assert work.count('input = 922000;') == 3
    assert 'context = 1048576;' in work
    assert 'output = 393216;' in work
    assert 'deepseek-v4-flash' not in opencode
    assert 'deepseek-v4-pro' not in opencode

    assert 'sops.secrets."opencode/work_key"' in client
    assert 'path = "/run/secrets/opencode/work_key";' in client
    assert "work_key: ENC[" in secrets
