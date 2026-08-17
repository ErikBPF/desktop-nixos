import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[2]
JUSTFILE = ROOT / "justfile"
WORKFLOW = ROOT / ".github/workflows/check.yml"


def test_stateless_orion_owner_cleanup_is_narrow_and_delegates_restart():
    source = JUSTFILE.read_text()
    recipe = source.split("orion-retire-legacy-llama:", 1)[1].split("\n# ", 1)[0]
    for value in (
        'IP="$(just _host-ip orion)"',
        'test "$(hostname)" = orion',
        'label=com.docker.compose.project=homelab',
        'label=com.docker.compose.service=llama-chat',
        '[[ "${#ids[@]}" -le 1 ]]',
        'if [[ "${#ids[@]}" -eq 1 ]]; then',
        '.Name == "/llama-chat"',
        '.Config.Labels["com.docker.compose.project.working_dir"] == "/home/erik/homelab"',
        '.Config.Labels["com.docker.compose.project.config_files"] == "ai-models.yml"',
        'systemctl --user stop podman-compose-ai-models.service',
        'docker stop --time 30 -- "$legacy_id"',
        'docker rm -- "$legacy_id"',
        "just kick-stack orion ai-models",
    ):
        assert value in recipe
    assert recipe.index("docker stop --time 30") < recipe.index("docker rm --")
    assert "docker rm -f" not in recipe
    assert "--remove-orphans" not in recipe
    assert "pytest -q tests/orion-owner-cutover/test_contract.py" in WORKFLOW.read_text()
