"""Open a captive Wi-Fi login window once per NetworkManager activation."""

import json
import os
from pathlib import Path
import socket
import subprocess
import sys


def open_portals(owner, connections, state, launch):
    if not owner:
        return
    opened = set(json.loads(state.read_text())) if state.exists() else set()
    for path, captive in connections:
        key = f'{owner}{path}'
        if not captive or key in opened:
            continue
        # Reserve before spawning so a listener restart cannot duplicate a window.
        opened.add(key)
        temporary = state.with_suffix('.tmp')
        temporary.write_text(json.dumps(sorted(opened)))
        temporary.replace(state)
        try:
            launch()
        except (OSError, subprocess.CalledProcessError):
            opened.remove(key)
            temporary.write_text(json.dumps(sorted(opened)))
            temporary.replace(state)
            raise


def wifi_connections(client, nm):
    connections = []
    for device in client.get_devices():
        active = device.get_active_connection()
        if (device.get_device_type() != nm.DeviceType.WIFI
                or device.get_state() != nm.DeviceState.ACTIVATED or not active):
            continue
        captive = any(device.get_connectivity(family) == nm.ConnectivityState.PORTAL
                      for family in (socket.AF_INET, socket.AF_INET6))
        connections.append((active.get_path(), captive))
    return connections


def main():
    import gi
    gi.require_version('NM', '1.0')
    from gi.repository import GLib, NM

    state = Path(os.environ['RUNTIME_DIRECTORY']) / 'opened.json'
    client = NM.Client.new(None)
    loop = GLib.MainLoop()

    def reconcile(*_args):
        try:
            open_portals(client.get_dbus_name_owner(), wifi_connections(client, NM),
                         state, lambda: subprocess.run(sys.argv[1:], check=True))
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f'Captive portal listener: {error}', file=sys.stderr, flush=True)
        return GLib.SOURCE_REMOVE

    def watch(_client, device):
        device.connect('notify', lambda *_: GLib.idle_add(reconcile))
        GLib.idle_add(reconcile)

    client.connect('device-added', watch)
    client.connect('notify::dbus-name-owner', lambda *_: GLib.idle_add(reconcile))
    for device in client.get_devices():
        watch(client, device)
    GLib.idle_add(reconcile)
    loop.run()


if __name__ == '__main__':
    main()
