"""Test evaluated launcher arguments against a disposable HTTP captive portal.

Usage: python3 tests/captive-portal/browser_smoke.py SERVICE_JSON
Export SERVICE_JSON with nix eval of the captive-portal unit's Service attribute.
"""
import http.server
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import threading
import uuid

requests = []
observed = threading.Event()


class Portal(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_CONNECT(self):
        requests.append(('HTTPS', self.path))
        self.send_error(502)
        if self.path == 'nmcheck.gnome.org:443':
            observed.set()

    def do_GET(self):
        requests.append(('HTTP', self.path))
        if self.path == 'http://portal.test/login':
            body = b'<html><body>Sign in<script>fetch("http://portal.test/rendered")</script></body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == 'http://nmcheck.gnome.org/check_network_status.txt':
            self.send_response(302)
            self.send_header('Location', 'http://portal.test/login')
            self.end_headers()
        else:
            self.send_response(204)
            self.end_headers()
            if self.path == 'http://portal.test/rendered':
                observed.set()


service = json.loads(Path(sys.argv[1]).read_text())
argv = shlex.split(service['ExecStart'][0])
browser_index = next(i for i, arg in enumerate(argv) if arg.endswith('/bin/brave'))
launcher = argv[2:browser_index]
argv = argv[browser_index:]
assert '--user-data-dir=%t/captive-portal/browser' in argv, 'Refusing to use the normal browser profile'
proxy = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Portal)
thread = threading.Thread(target=proxy.serve_forever, daemon=True)
thread.start()
try:
    for scheme in ('http', 'https'):
        requests.clear()
        observed.clear()
        with tempfile.TemporaryDirectory(prefix='captive-browser-smoke-') as runtime:
            args = [arg.replace('%t', runtime) for arg in argv[:-1]]
            unit = 'captive-portal-smoke-' + uuid.uuid4().hex
            subprocess.run([*launcher, '--unit=' + unit,
                *args, '--headless', '--disable-background-networking',
                '--disable-component-update', '--disable-sync',
                f'--proxy-server=http://127.0.0.1:{proxy.server_port}',
                argv[-1].replace('http://', scheme + '://', 1),
            ], check=True, timeout=10)
            try:
                assert observed.wait(20), f'No page-load event; requests={requests}'
                if scheme == 'http':
                    assert ('HTTP', argv[-1]) in requests, requests
                    assert ('HTTP', 'http://portal.test/rendered') in requests, requests
                    assert not any(kind == 'HTTPS' and host.split(':')[0] in
                                   ('nmcheck.gnome.org', 'portal.test')
                                   for kind, host in requests), requests
                else:
                    assert ('HTTPS', 'nmcheck.gnome.org:443') in requests, requests
            finally:
                subprocess.run(['systemctl', '--user', 'stop', unit], check=True, timeout=10)
    print('PASS: HTTP probe and login redirect rendered without HTTPS upgrades; HTTPS control detected')
finally:
    proxy.shutdown()
    proxy.server_close()
    thread.join()
