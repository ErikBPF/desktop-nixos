"""NoiseTorch source choice: explicit device order before PipeWire priority."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
PROGRAM = ROOT / 'modules/desktop/noisetorch-mic.jq'


def source(name, description, priority):
    return {'info': {'props': {
        'media.class': 'Audio/Source',
        'node.name': name,
        'node.description': description,
        'priority.session': priority,
    }}}


HOLLY = source(
    'alsa_input.usb-Shenzhen_Hollyland_Technology_Co._Ltd_Wireless_microphone_95HX2G39FL3-01.analog-stereo',
    'Wireless microphone Analog Stereo', 2109)
BUILTIN = source(
    'alsa_input.pci-0000_00_1f.3.analog-stereo',
    'Built-in Audio Analog Stereo', 2009)
SCARLETT = source(
    'alsa_input.usb-Focusrite_Scarlett_2i2_USB-00.analog-stereo',
    'Scarlett 2i2 USB Analog Stereo', 1900)
ALIEN = source(
    'alsa_input.usb-Unknown-01.analog-stereo',
    'Unknown USB microphone', 2500)
VIRTUAL = source(
    'effect_output.noisetorch',
    'NoiseTorch Microphone (RNNoise)', 2000)


def pick(objects):
    result = subprocess.run(
        ['jq', '-r', '-f', str(PROGRAM)],
        input=json.dumps(objects), capture_output=True, text=True, check=True)
    return result.stdout.strip()


class MicPriority(unittest.TestCase):
    def test_hollyland_beats_builtin_and_a_higher_priority_unknown_mic(self):
        self.assertEqual(pick([ALIEN, BUILTIN, HOLLY]), HOLLY['info']['props']['node.name'])

    def test_hollyland_beats_scarlett_even_when_scarlett_has_higher_priority(self):
        hot_scarlett = source(SCARLETT['info']['props']['node.name'],
                              SCARLETT['info']['props']['node.description'], 2400)
        cold_holly = source(HOLLY['info']['props']['node.name'],
                            HOLLY['info']['props']['node.description'], 1500)
        self.assertEqual(pick([hot_scarlett, cold_holly]), HOLLY['info']['props']['node.name'])

    def test_scarlett_is_second_choice(self):
        self.assertEqual(pick([BUILTIN, SCARLETT]), SCARLETT['info']['props']['node.name'])

    def test_builtin_is_third_choice_even_below_an_unknown_higher_priority_mic(self):
        self.assertEqual(pick([ALIEN, BUILTIN]), BUILTIN['info']['props']['node.name'])

    def test_unknown_mic_still_works_when_it_is_the_only_candidate(self):
        self.assertEqual(pick([ALIEN]), ALIEN['info']['props']['node.name'])

    def test_virtual_source_is_never_selected_as_capture(self):
        self.assertEqual(pick([VIRTUAL, BUILTIN]), BUILTIN['info']['props']['node.name'])

    def test_audio_module_uses_the_shared_program(self):
        module = (ROOT / 'modules/desktop/audio.nix').read_text()
        self.assertIn('noisetorch-mic.jq', module)


if __name__ == '__main__':
    unittest.main()
