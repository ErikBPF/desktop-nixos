"""Explicit installed-controller E2E using a virtual source and synthetic WAV.

Requires an explicitly isolated Wayland display, idle worker and plain-text/empty
clipboard. Set VOICE_E2E_ISOLATED_DISPLAY to that disposable display name. Preserves the
clipboard in memory, never prints it, and removes its runtime overrides afterward.
"""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import json


def command(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def wait(predicate, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.1)
    raise AssertionError('Timed out waiting for the dictation lifecycle')


def property_of(unit, name):
    return command(['systemctl', '--user', 'show', unit, '-p', name, '--value']).stdout.strip().decode()


def inactive(unit):
    return property_of(unit, 'ActiveState') not in ('active', 'activating', 'deactivating')


assert os.environ.get('VOICE_E2E_ISOLATED_DISPLAY') and os.environ.get('VOICE_E2E_ISOLATED_DISPLAY') == os.environ.get('WAYLAND_DISPLAY'), 'Run only with an explicitly isolated test compositor'
fixture = Path(sys.argv[1]).resolve()
assert fixture.is_file(), 'Supply the synthetic English fixture'
units = ['voice-dictation@plain.service', 'voice-dictation@context.service']
assert all(inactive(unit) for unit in units), 'A user capture is already active'
home = Path.home()
config = home / '.config'
unit_text = (config / 'systemd/user/voice-dictation@.service').read_text()
variables = [value for line in re.findall(r'^Environment=(.*)$', unit_text, re.M) for value in shlex.split(line)]
runtime_path = next(value[5:] for value in variables if value.startswith('PATH='))
programs = {name: shutil.which(name, path=runtime_path) for name in ('voxtype', 'pw-record', 'notify-send', 'wl-copy', 'wl-paste')}
assert all(programs.values()), 'Installed runtime tools are incomplete'
controller = re.search(r'"(/nix/store/[^" ]+/bin/voice-dictation) toggle plain"', (config / 'hypr/hyprland.lua').read_text()).group(1)
offered = subprocess.run([programs['wl-paste'], '--list-types'], capture_output=True)
types = offered.stdout.decode().splitlines()
plain_types = {'UTF8_STRING', 'TEXT', 'STRING', 'TARGETS', 'TIMESTAMP', 'SAVE_TARGETS', 'MULTIPLE', 'text/plain', 'text/plain;charset=utf-8'}
assert set(types) <= plain_types, 'Rich/binary clipboard: use manual E2E instead'
old = subprocess.run([programs['wl-paste'], '--no-newline'], capture_output=True)


def clipboard():
    return command([programs['wl-paste'], '--no-newline', '--type', 'text']).stdout


def copy(value):
    subprocess.run([programs['wl-copy']], input=value, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


runtime = Path(os.environ['XDG_RUNTIME_DIR'])
dropin = runtime / 'systemd/user/voice-dictation@.service.d/zz-voice-migration-test.conf'
assert not dropin.exists(), 'Existing test override must be reconciled first'
owned_values = set()
active_unit = None
active_invocation = None
loop = None
with tempfile.TemporaryDirectory(prefix='voice-e2e-') as directory:
    directory = Path(directory)
    events = directory / 'events'
    asr = directory / 'local-asr'
    for name, extra in {
        'pw-record': '--target=voice-migration-test-source --properties=node.name=voice-migration-capture',
        'voxtype': '',
        'notify-send': '',
    }.items():
        record = ''
        if name == 'voxtype':
            record = f'printf "local-asr\\n" >> {shlex.quote(str(asr))}\n'
        if name == 'notify-send':
            record = f'printf "%s\\n" "$@" >> {shlex.quote(str(events))}\n'
        wrapper = directory / name
        wrapper.write_text(f'#!/bin/sh\n{record}exec {shlex.quote(programs[name])} {extra} "$@"\n')
        wrapper.chmod(0o700)

    def override(force_local):
        key = directory / 'absent-key' if force_local else config / 'voice-dictation/litellm-api-key'
        dropin.parent.mkdir(parents=True, exist_ok=True)
        display = os.environ['WAYLAND_DISPLAY']
        assert re.fullmatch(r'[a-zA-Z0-9._-]+', display), 'Unsupported test display name'
        dropin.write_text(f'[Service]\nEnvironment="PATH={directory}:{runtime_path}"\nEnvironment="VOICE_API_KEY_FILE={key}"\nEnvironment="WAYLAND_DISPLAY={display}"\n')
        command(['systemctl', '--user', 'daemon-reload'])
        effective = shlex.split(property_of(units[0], 'Environment'))
        assert f'PATH={directory}:{runtime_path}' in effective, 'Virtual capture wrapper not active'
        assert f'WAYLAND_DISPLAY={display}' in effective, 'Isolated clipboard display not active'

    def virtual_linked():
        objects = json.loads(command(['pw-dump']).stdout)
        nodes = {o['id']: o.get('info', {}).get('props', {}).get('node.name') for o in objects if o['type'].endswith(':Node')}
        return any(o['type'].endswith(':Link') and nodes.get(o.get('info', {}).get('output-node-id')) == 'voice-migration-test-source' and nodes.get(o.get('info', {}).get('input-node-id')) == 'voice-migration-capture' for o in objects)

    try:
        loop = subprocess.Popen(['pw-loopback', '--name', 'voice-migration-test', '--channels', '1', '--channel-map', 'MONO', '--capture-props', 'media.class=Audio/Sink node.name=voice-migration-test-sink priority.session=-1000', '--playback-props', 'media.class=Audio/Source node.name=voice-migration-test-source priority.session=-1000'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
        for mode, force_local in [('plain', False), ('context', False), ('context', True)]:
            override(force_local)
            events.unlink(missing_ok=True)
            asr.unlink(missing_ok=True)
            context = b'Can you fix the server error and verify the tests?'
            copy(context); owned_values.add(context)
            active_unit = f'voice-dictation@{mode}.service'
            command([controller, 'toggle', mode])
            active_invocation = property_of(active_unit, 'InvocationID')
            wait(virtual_linked, 10)
            command(['pw-play', '--target=voice-migration-test-sink', str(fixture)])
            time.sleep(.6)
            start = time.monotonic()
            command([controller, 'toggle', mode])
            wait(lambda: inactive(active_unit))
            assert property_of(active_unit, 'Result') == 'success', 'Worker failed'
            active_unit = None
            result = clipboard()
            owned_values.add(result)
            lowered = result.lower()
            assert b'fix' in lowered and b'tests' in lowered and result != context, 'Synthetic result did not meet the expected actions'
            assert asr.exists() == force_local, 'ASR used the wrong route'
            degraded = events.read_text().count('Using local fallback')
            if force_local:
                assert degraded == 2, 'Both stages must use local fallback'
            time.sleep(1)
            assert clipboard() == result, 'Clipboard owner died with the worker'
            assert not list((runtime / 'voice-dictation').glob('capture-*')), 'Private capture files leaked'
            print(f'mode={mode} forced_local={force_local} fallback_notices={degraded} stop_to_check_seconds={time.monotonic()-start:.2f}', flush=True)
        override(False)
        sentinel = b'VOICE_CANCEL_SENTINEL'
        copy(sentinel); owned_values.add(sentinel)
        active_unit = units[0]
        command([controller, 'toggle', 'plain'])
        active_invocation = property_of(active_unit, 'InvocationID')
        wait(virtual_linked, 10)
        command([controller, 'toggle', 'cancel'])
        wait(lambda: inactive(active_unit), 15)
        active_unit = None
        assert clipboard() == sentinel, 'Cancellation changed the clipboard'
        assert not list((runtime / 'voice-dictation').glob('capture-*')), 'Cancelled audio leaked'
        print('VOICE_GATEWAY_CAPTURE_E2E_OK', flush=True)
    finally:
        if active_unit and property_of(active_unit, 'InvocationID') == active_invocation:
            command(['systemctl', '--user', 'stop', active_unit])
        dropin.unlink(missing_ok=True)
        command(['systemctl', '--user', 'daemon-reload'])
        if loop:
            loop.terminate(); loop.wait(timeout=5)
        # Preserve a new clipboard selection made by the user during the test.
        current = subprocess.run([programs['wl-paste'], '--no-newline', '--type', 'text'], capture_output=True)
        if not current.returncode and current.stdout in owned_values:
            if old.returncode:
                command([programs['wl-copy'], '--clear'])
            else:
                copy(old.stdout)
