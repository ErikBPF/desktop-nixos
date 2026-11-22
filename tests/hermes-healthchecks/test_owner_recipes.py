"""Execute owner recipe fragments against the two shipped Python environments."""
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "just/hermes.just"


def recipe(name):
    source = SOURCE.read_text()
    marker = name + ":\n"
    if marker not in source:
        return ""
    lines = source.split(marker, 1)[1].splitlines()
    body = []
    for line in lines:
        if line and not line.startswith("    "):
            break
        body.append(line[4:])
    return "\n".join(body)


class OwnerRecipeTests(unittest.TestCase):
    def test_models_use_each_container_installed_runtime(self):
        body = recipe("hermes-agents-health")
        loop = body[body.index("for name in hermes-daedalus hermes-argus;"):]
        loop = loop[:loop.index("done") + 4]
        with tempfile.TemporaryDirectory() as directory:
            docker = Path(directory) / "docker"
            docker.write_text("#!/usr/bin/env python3\n" + textwrap.dedent('''
                import builtins, io, json, os, sys, types, urllib.request
                _, name, interpreter, flag, code = sys.argv[1:]
                assert flag == '-c'
                original_import = builtins.__import__
                config = {'model': {'default': 'fixture-model'}}
                def import_module(module, *args, **kwargs):
                    if module == 'yaml':
                        if name == 'hermes-argus':
                            raise ModuleNotFoundError("No module named 'yaml'")
                        return types.SimpleNamespace(safe_load=lambda file: config)
                    if module == 'ruamel.yaml':
                        assert name == 'hermes-argus'
                        assert interpreter == '/opt/hermes/.venv/bin/python'
                        return types.SimpleNamespace(YAML=lambda **kw: types.SimpleNamespace(load=lambda file: config))
                    return original_import(module, *args, **kwargs)
                builtins.__import__ = import_module
                builtins.open = lambda *args, **kwargs: io.StringIO('fixture')
                urllib.request.urlopen = lambda *args, **kwargs: io.StringIO(json.dumps({'data':[{'id':('unauthorized-model' if os.environ.get('DENY_CONTAINER') == name else 'fixture-model')}]}))
                os.environ.update(OPENAI_BASE_URL='https://fixture.invalid', OPENAI_API_KEY='fixture-only')
                exec(code)
            '''))
            docker.chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', loop], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in ['hermes-daedalus', 'hermes-argus']:
                env['DENY_CONTAINER'] = name
                denied = subprocess.run(['bash', '-euo', 'pipefail', '-c', loop], env=env, capture_output=True, text=True)
                self.assertNotEqual(denied.returncode, 0, name)

    def test_scoped_render_accepts_unchanged_siblings_and_checks_metadata(self):
        body = recipe('verify-hermes-argus-render') or recipe('verify-hermes-secret-renders')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for name, script in {
                'just': 'printf "fixture-host\\n"',
                'ssh': 'bash -c "${@: -1}"',
                'sudo': 'exec "$@"',
                'systemctl': 'for unit in "$@"; do case "$unit" in *.service) [ "$unit" != "${INACTIVE_UNIT:-}" ] && exit 0 ;; esac; done; exit 1',
                'stat': 'printf "%s\\n" "${RENDER_METADATA:-400 root vault-consumers}"',
                'test': '[ "$1" = -s ] && [ "${RENDER_NONEMPTY:-1}" = 1 ]',
                'find': 'exit 1',  # unchanged sibling renders are older than fifteen minutes
            }.items():
                file = path / name
                file.write_text('#!/usr/bin/env bash\n' + script + '\n')
                file.chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'])
            for changes, success in [({}, True), ({'RENDER_METADATA': '644 root root'}, False), ({'INACTIVE_UNIT': 'vault-agent.service'}, False), ({'INACTIVE_UNIT': 'docker-hermes-argus.service'}, False), ({'RENDER_NONEMPTY': '0'}, False)]:
                result = subprocess.run(['bash', '-c', body], env=dict(env, **changes), capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)


if __name__ == '__main__':
    unittest.main()
