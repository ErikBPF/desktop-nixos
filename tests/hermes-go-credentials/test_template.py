"""Run the actual Consul Template transformation against synthetic dotenv inputs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_scoped_key_alias_preserves_dotenv_and_pins_proxy():
    source = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()
    for field in ("SERVER_ENV", "DAEDALUS_ENV", "ARGUS_ENV"):
        assert '${hermesEnv "' + field + '"}' in source
    encoded = source.split("hermesEnv = field: ''", 1)[1].split("'';", 1)[0]
    template = json.loads('"' + encoded + '"')
    template = template.replace('with secret "secret/data/home/hermes"', 'with env "HERMES_TEST_ENV"')
    template = template.replace('.Data.data.${field}', '.')
    for fixture, expected_key in (
        ("OPENAI_API_KEY=synthetic-scoped\nOTHER=keep\n", "synthetic-scoped"),
        ('OTHER=keep\nOPENAI_API_KEY="test=test"', '"test=test"'),
        ("NOT_OPENAI_API_KEY=ignore\n", None),
    ):
        with tempfile.TemporaryDirectory() as directory:
            src, dst = Path(directory) / "input.tpl", Path(directory) / "output.env"
            src.write_text(template)
            subprocess.run(
                [os.environ.get("CONSUL_TEMPLATE", "consul-template"), "-once", "-template", f"{src}:{dst}"],
                env={**os.environ, "HERMES_TEST_ENV": fixture},
                check=True, capture_output=True, timeout=15,
            )
            output = dst.read_text()
            assert "OPENCODE_GO_BASE_URL=http://litellm:4000/v1\n" in output
            for line in fixture.splitlines():
                assert line in output.splitlines()
            if expected_key is None:
                assert "\nOPENCODE_GO_API_KEY=" not in output
            else:
                assert f"OPENCODE_GO_API_KEY={expected_key}" in output.splitlines()
