import importlib.util
from pathlib import Path
import tempfile
import socket
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

SOURCE = Path(__file__).resolve().parents[2] / 'modules/desktop/_captive_portal.py'
spec = importlib.util.spec_from_file_location('portal', SOURCE)
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)


class PortalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name) / 'opened.json'
        self.launch = Mock()

    def update(self, connections, owner=':1.10'):
        portal.open_portals(owner, connections, self.state, self.launch)

    def test_opens_once_despite_repeated_detection_and_status_flapping(self):
        self.update([('/active/1', True)])
        self.update([('/active/1', True)])
        self.update([('/active/1', False)])
        self.update([('/active/1', True)])
        self.launch.assert_called_once_with()

    def test_normal_and_offline_connections_never_open(self):
        self.update([])
        self.update([('/active/1', False)])
        self.launch.assert_not_called()

    def test_reconnect_opens_again_even_if_disconnect_event_was_missed(self):
        self.update([('/active/1', True)])
        self.update([('/active/2', True)])
        self.assertEqual(self.launch.call_count, 2)

    def test_multiple_interfaces_each_open_once(self):
        for _ in range(2):
            self.update([('/active/1', True), ('/active/2', True)])
        self.assertEqual(self.launch.call_count, 2)

    def test_restart_preserves_deduplication(self):
        self.update([('/active/1', True)])
        spec.loader.exec_module(portal)
        self.update([('/active/1', True)])
        self.launch.assert_called_once_with()

    def test_networkmanager_restart_can_reuse_object_path(self):
        self.update([('/active/1', True)])
        self.update([('/active/1', True)], owner=':1.20')
        self.assertEqual(self.launch.call_count, 2)

    def test_missing_networkmanager_does_not_open(self):
        self.update([('/active/1', True)], owner=None)
        self.launch.assert_not_called()

    def test_failed_exec_can_retry(self):
        self.launch.side_effect = [OSError('browser missing'), None]
        with self.assertRaises(OSError):
            self.update([('/active/1', True)])
        self.update([('/active/1', True)])
        self.assertEqual(self.launch.call_count, 2)

    def test_failed_launcher_can_retry(self):
        self.launch.side_effect = [subprocess.CalledProcessError(1, 'systemd-run'), None]
        with self.assertRaises(subprocess.CalledProcessError):
            self.update([('/active/1', True)])
        self.update([('/active/1', True)])
        self.assertEqual(self.launch.call_count, 2)


class DeviceTest(unittest.TestCase):
    def test_only_activated_wifi_portals_in_either_ip_family(self):
        nm = SimpleNamespace(DeviceType=SimpleNamespace(WIFI=2),
                             DeviceState=SimpleNamespace(ACTIVATED=100),
                             ConnectivityState=SimpleNamespace(PORTAL=2))
        devices = []
        for name, kind, state, ip4, ip6, active in [
            ('v4', 2, 100, 2, 0, True), ('v6', 2, 100, 0, 2, True),
            ('online', 2, 100, 4, 4, True), ('limited', 2, 100, 3, 3, True),
            ('wired', 1, 100, 2, 2, True), ('vpn', 16, 100, 2, 2, True),
            ('connecting', 2, 50, 2, 2, True), ('inactive', 2, 100, 2, 2, False),
        ]:
            device = Mock()
            device.get_device_type.return_value = kind
            device.get_state.return_value = state
            device.get_active_connection.return_value = (
                Mock(get_path=Mock(return_value='/' + name)) if active else None)
            device.get_connectivity.side_effect = {
                socket.AF_INET: ip4, socket.AF_INET6: ip6}.__getitem__
            devices.append(device)
        client = Mock(get_devices=Mock(return_value=devices))
        self.assertEqual(portal.wifi_connections(client, nm),
                         [('/v4', True), ('/v6', True),
                          ('/online', False), ('/limited', False)])


if __name__ == '__main__':
    unittest.main()
