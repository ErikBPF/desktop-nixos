"""Run with sudo unshare --net python tests/openbao-ingress/test_network.py.

Uses disposable network namespaces; never changes the host's firewall.
"""
import os
from pathlib import Path
import subprocess as sp
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]

def run(*args):
    return sp.check_output(args, text=True).strip()

assert os.geteuid() == 0, 'run inside sudo unshare --net'
assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'refuse host namespace'
client, server = [f'bao-{uuid.uuid4().hex[:8]}' for _ in range(2)]
process = None
try:
    for name in (client, server):
        run('ip', 'netns', 'add', name)
    for router_if, peer, ns, router_ip, peer_ip in (
        ('tailscale0', 'client0', client, '100.100.0.1/24', '100.100.0.2/24'),
        ('br-test', 'server0', server, '172.18.0.1/24', '172.18.0.2/24'),
    ):
        run('ip', 'link', 'add', router_if, 'type', 'veth', 'peer', 'name', peer)
        run('ip', 'link', 'set', peer, 'netns', ns)
        run('ip', 'addr', 'add', router_ip, 'dev', router_if)
        run('ip', 'link', 'set', router_if, 'up')
        run('ip', '-n', ns, 'addr', 'add', peer_ip, 'dev', peer)
        run('ip', '-n', ns, 'link', 'set', peer, 'up')
        run('ip', '-n', ns, 'link', 'set', 'lo', 'up')
        run('ip', '-n', ns, 'route', 'add', 'default', 'via', router_ip.split('/')[0])
    run('ip', 'link', 'set', 'lo', 'up')
    run('sysctl', '-qw', 'net.ipv4.ip_forward=1')
    for addr in ('192.168.10.210', '100.76.140.121'):
        run('ip', 'addr', 'add', addr+'/32', 'dev', 'lo')
        for port in ('443', '8443'):
            run('iptables', '-t', 'nat', '-A', 'PREROUTING', '-d', addr, '-p', 'tcp', '--dport', port,
                '-j', 'DNAT', '--to-destination', '172.18.0.2:'+port)
    run('iptables', '-A', 'FORWARD', '-i', 'tailscale0', '-j', 'MARK', '--set-xmark', '0x40000/0xff0000')
    run('iptables', '-t', 'nat', '-A', 'POSTROUTING', '-m', 'mark', '--mark', '0x40000/0xff0000', '-j', 'MASQUERADE')
    code = '''import http.server,threading
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200);self.end_headers();self.wfile.write(self.client_address[0].encode())
 def log_message(self,*args): pass
for port in (443,8443):
 s=http.server.HTTPServer(('0.0.0.0',port),Handler)
 threading.Thread(target=s.serve_forever,daemon=True).start()
print('ready',flush=True)
threading.Event().wait()
'''
    process = sp.Popen(['ip','netns','exec',server,sys.executable,'-c',code], stdout=sp.PIPE, text=True)
    assert process.stdout.readline().strip() == 'ready'
    run('ip','-n',client,'addr','add','198.51.100.2/32','dev','client0')
    run('ip','route','add','198.51.100.2/32','via','100.100.0.2')
    script = ROOT/'modules/hosts/discovery/_preserve-ingress-source.sh'
    if script.exists():
        for _ in range(2):  # installation must be idempotent
            run('bash',str(script),'add','192.168.10.210','100.76.140.121')
    def source(addr, port):
        code=f"import urllib.request;print(urllib.request.urlopen('http://{addr}:{port}',timeout=3).read().decode())"
        return run('ip','netns','exec',client,sys.executable,'-c',code)
    for addr in ('192.168.10.210','100.76.140.121'):
        assert source(addr,443) == '100.100.0.2', 'HTTPS client identity lost to SNAT'
        assert source(addr,8443) == '172.18.0.1', 'unrelated port SNAT changed'
    code = "import http.client;c=http.client.HTTPConnection('192.168.10.210',443,timeout=3,source_address=('198.51.100.2',0));c.request('GET','/');print(c.getresponse().read().decode())"
    assert run('ip','netns','exec',client,sys.executable,'-c',code) == '172.18.0.1', 'non-tailnet source matched exception'
    assert source('172.18.0.2',443) == '172.18.0.1', 'direct container SNAT changed'
    for _ in range(2):
        run('bash',str(script),'remove','192.168.10.210','100.76.140.121')
    assert source('192.168.10.210',443) == '172.18.0.1', 'cleanup failed'
    print('PASS: client identity, port scope, destination scope, idempotence, cleanup')
finally:
    if process:
        process.terminate(); process.wait(timeout=5); process.stdout.close()
    for name in (client, server):
        sp.run(['ip','netns','del',name],check=False,stdout=sp.DEVNULL,stderr=sp.DEVNULL)
