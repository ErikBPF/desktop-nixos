"""Disposable pinned Wazuh TLS enrollment proof; run explicitly with pytest.

Uses only synthetic certificates/identity and loopback. Pull the pinned image
before running; never mounts host Wazuh state or contacts the live manager.
"""
import hashlib
import os
import re
import socket
import ssl
import subprocess
import threading
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

ENGINE = os.environ.get("WAZUH_CONTAINER_ENGINE", "podman")
ROOT = Path(__file__).parents[2]
IMAGE = re.search(r'image = "([^"]+wazuh-agent[^"]+)"',
                  (ROOT / 'modules/hosts/orion/wazuh-agent.nix').read_text())[1]


def openssl(directory, *args):
    subprocess.run(['openssl', *args], cwd=directory, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=20)


@pytest.fixture(scope='module')
def certificates(tmp_path_factory):
    directory = tmp_path_factory.mktemp('wazuh-trust')
    for ca in ('trusted', 'untrusted'):
        openssl(directory, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                '-days', '1', '-subj', f'/CN=disposable-{ca}',
                '-keyout', f'{ca}.key', '-out', f'{ca}.pem',
                '-addext', 'basicConstraints=critical,CA:TRUE')
    for name, ca, address in [('trusted', 'trusted', '127.0.0.1'),
                              ('untrusted', 'untrusted', '127.0.0.1'),
                              ('wrong-name', 'trusted', '127.0.0.2')]:
        openssl(directory, 'req', '-newkey', 'rsa:2048', '-nodes',
                '-subj', '/CN=fixture.invalid', '-keyout', f'{name}-server.key',
                '-out', f'{name}.csr')
        (directory / 'extensions').write_text(
            f'subjectAltName=IP:{address}\nextendedKeyUsage=serverAuth\n')
        openssl(directory, 'x509', '-req', '-in', f'{name}.csr',
                '-CA', f'{ca}.pem', '-CAkey', f'{ca}.key', '-CAcreateserial',
                '-days', '1', '-extfile', 'extensions', '-out', f'{name}-server.pem')
    # Existing manager uses a persistent self-signed v1 certificate, CN only.
    openssl(directory, 'req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=127.0.0.1',
            '-keyout', 'self-signed-server.key', '-out', 'self-signed.csr')
    openssl(directory, 'x509', '-req', '-in', 'self-signed.csr',
            '-signkey', 'self-signed-server.key', '-days', '1', '-out', 'self-signed-server.pem')
    return directory


def enrollment(directory, certificate, verify=None, anchor='trusted.pem'):
    if verify is None:
        config = ET.parse(ROOT / 'modules/hosts/orion/wazuh-agent.xml')
        verify = config.findtext('client/enrollment/server_ca_path') is not None
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(directory / f'{certificate}-server.pem',
                            directory / f'{certificate}-server.key')
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    listener.settimeout(1)
    port = listener.getsockname()[1]
    received = []
    failures = []
    stop = threading.Event()

    def manager():
        try:
            with listener:
                while True:
                    try:
                        connection, _ = listener.accept()
                        break
                    except TimeoutError:
                        if stop.is_set():
                            return
                connection.settimeout(5)
                with context.wrap_socket(connection, server_side=True) as connection:
                    message = connection.recv(4096)
                    if message:
                        received.append(message)
                        # Synthetic fixture identity; never a production key.
                        connection.sendall(b"OSSEC K:'001 s06-fixture any " + b'1' * 64 + b"'\n\n")
        except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
            pass  # Expected when the real client rejects the server.
        except Exception as error:
            failures.append(error)

    thread = threading.Thread(target=manager, daemon=True)
    thread.start()
    name = 'wazuh-s06-' + uuid.uuid4().hex
    command = [ENGINE, 'run', '--rm', '--pull=never', '--name', name,
               '--network=host', '--memory=256m', '--cpus=1',
               '--volume', f'{directory}:/fixtures:ro',
               '--entrypoint', '/var/ossec/bin/agent-auth', IMAGE,
               '-m', '127.0.0.1', '-p', str(port), '-A', 's06-fixture',
               '-P', 'disposable-not-a-secret']
    if verify:
        command += ['-v', f'/fixtures/{anchor}']
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=15)
    finally:
        subprocess.run([ENGINE, 'rm', '-f', name], capture_output=True, timeout=10)
        stop.set()
        thread.join(timeout=6)
        listener.close()
    assert not thread.is_alive(), 'fixture manager did not terminate'
    # A missing CA fails before connecting, so no accepted socket is expected.
    if anchor != 'missing.pem':
        assert not failures, failures
    return result, received


def test_trusted_manager_accepts_synthetic_identity(certificates):
    result, received = enrollment(certificates, 'trusted')
    assert result.returncode == 0, result.stderr
    assert 'Valid key received' in result.stdout + result.stderr
    assert len(received) == 1


@pytest.mark.parametrize('certificate', ['untrusted', 'wrong-name'])
def test_rejects_before_sending_enrollment_password(certificates, certificate):
    result, received = enrollment(certificates, certificate)
    assert result.returncode != 0
    assert received == [], 'enrollment password reached an untrusted or wrong manager'


def test_missing_anchor_fails_closed(certificates):
    result, received = enrollment(certificates, 'trusted', anchor='missing.pem')
    assert result.returncode != 0
    assert received == []


def test_persisted_self_signed_cn_only_leaf_is_usable_anchor(certificates):
    result, received = enrollment(certificates, 'self-signed', anchor='self-signed-server.pem')
    assert result.returncode == 0, result.stderr
    assert len(received) == 1


def test_image_init_preserves_trust_endpoint_and_existing_identity(tmp_path):
    source = (ROOT / 'modules/hosts/orion/wazuh-agent.nix').read_text()
    keys = tmp_path / 'client.keys'
    keys.write_text('001 s06-fixture any ' + '1' * 64 + '\n')
    before = hashlib.sha256(keys.read_bytes()).hexdigest()
    environment = []
    for name, value in re.findall(r'(WAZUH_[A-Z_]+) = "([^"\n]+)";', source):
        environment += ['--env', f'{name}={value}']
    for _ in range(2):
        result = subprocess.run([
            ENGINE, 'run', '--rm', '--pull=never', '--network=none',
            '--volume', f'{ROOT / "modules/hosts/orion/wazuh-agent.xml"}:/wazuh-config-mount/etc/ossec.conf:ro',
            '--volume', f'{ROOT / "modules/hosts/orion/wazuh-enrollment-ca.pem"}:/var/ossec/etc/enrollment-ca.pem:ro',
            '--volume', f'{keys}:/var/ossec/etc/client.keys',
            *environment, '--entrypoint', '/bin/bash', IMAGE, '-c',
            'bash /etc/cont-init.d/0-wazuh-init >/dev/null; '
            '/var/ossec/bin/wazuh-agentd -t >/dev/null 2>&1 || exit 1; '
            'cat /var/ossec/etc/ossec.conf',
        ], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stderr
        config = ET.fromstring(result.stdout)
        assert config.findtext('client/server/address') == '192.168.10.250'
        assert config.findtext('client/enrollment/manager_address') == 'wazuh-manager-master-0'
        assert config.findtext('client/enrollment/server_ca_path') == '/var/ossec/etc/enrollment-ca.pem'
        assert config.findtext('localfile/location') == '/var/log/wazuh-host/sshd.log'
        assert hashlib.sha256(keys.read_bytes()).hexdigest() == before
