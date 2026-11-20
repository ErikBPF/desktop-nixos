"""Keep captive login navigations out of the normal HTTPS-upgrading profile."""
from pathlib import Path
import re
import shlex
import unittest

MODULE = Path(__file__).resolve().parents[2] / 'modules/desktop/captive-portal.nix'


class BrowserConfigTest(unittest.TestCase):
    def test_login_has_its_own_runtime_profile_and_no_automatic_https_upgrade(self):
        command = re.search(r'ExecStart = "([^"]+)";', MODULE.read_text()).group(1)
        arguments = shlex.split(command)
        self.assertIn('--user-data-dir=%t/captive-portal/browser', arguments)
        disabled = next((arg.split('=', 1)[1] for arg in arguments
                         if arg.startswith('--disable-features=')), '')
        self.assertTrue({'BraveHttpsByDefault', 'HttpsUpgrades'} <= set(disabled.split(',')))
        self.assertEqual(arguments[-1], 'http://nmcheck.gnome.org/check_network_status.txt')
        self.assertNotIn('--ignore-certificate-errors', arguments)
        self.assertNotIn('--no-sandbox', arguments)


if __name__ == '__main__':
    unittest.main()
