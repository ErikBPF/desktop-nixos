import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
JUSTFILE = ROOT / "justfile"
WORKFLOW = ROOT / ".github/workflows/check.yml"


class StatelessOwnerCleanupTest(unittest.TestCase):
    def test_cleanup_is_narrow_retryable_and_delegates_restart(self):
        source = JUSTFILE.read_text()
        recipe = source.split("orion-retire-legacy-llama:", 1)[1].split(
            "\n# ", 1
        )[0]
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
            self.assertIn(value, recipe)
        self.assertLess(
            recipe.index("docker stop --time 30"), recipe.index("docker rm --")
        )
        self.assertNotIn("docker rm -f", recipe)
        self.assertNotIn("--remove-orphans", recipe)
        self.assertIn(
            "python -m unittest discover -s tests/orion-owner-cutover",
            WORKFLOW.read_text(),
        )
