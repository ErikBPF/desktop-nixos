"""Retired panel shortcuts stay absent; Endeavour keeps its voice shortcuts."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


class Bindings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        expression = '''configs: builtins.listToAttrs (map (host: {
          name = host;
          value = builtins.filter (binding: builtins.elem (builtins.head binding._args)
            [ "SUPER + I" "SUPER + U" "SUPER + CTRL + I" ])
            configs.${host}.config.home-manager.users.erik.wayland.windowManager.hyprland.settings.bind;
        }) [ "endeavour" "pathfinder" "orion" "challenger" ])'''
        result = subprocess.run(
            ['nix', 'eval', '--json', '.#nixosConfigurations', '--apply', expression],
            cwd=ROOT, capture_output=True, text=True, timeout=300, check=True)
        cls.bindings = json.loads(result.stdout)

    def test_endeavour_has_unique_voice_shortcuts(self):
        bindings = self.bindings['endeavour']
        self.assertEqual(len(bindings), 3)
        for key, mode in [('SUPER + U', 'plain'), ('SUPER + I', 'context'),
                          ('SUPER + CTRL + I', 'cancel')]:
            actions = [json.dumps(binding['_args'][1]) for binding in bindings
                       if binding['_args'][0] == key]
            self.assertEqual(len(actions), 1, key)
            self.assertIn(f'/bin/voice-dictation toggle {mode}', actions[0])

    def test_other_desktops_have_no_retired_panel_shortcuts(self):
        for host in ('pathfinder', 'orion', 'challenger'):
            with self.subTest(host=host):
                self.assertEqual(self.bindings[host], [], f'{host} still has retired panel shortcuts')
