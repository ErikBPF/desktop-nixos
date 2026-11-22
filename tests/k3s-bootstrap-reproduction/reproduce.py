"""Disposable exact-K3s bootstrap experiment; never uses the host network/state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, capture_output=True, **kwargs)


def inside(args):
    root = Path('/work')
    assert os.readlink('/proc/self/ns/net') != args.host_net
    assert not Path('/home/erik').exists()
    assert not Path('/etc/rancher').exists()
    assert not Path('/var/lib/rancher').exists()
    assert not Path('/run/k3s').exists()
    assert not run(['ip', 'route']).stdout.strip(), 'outer network must have no routes'
    assert 'v1.36.5+k3s1' in run([args.k3s, '--version']).stdout
    (root / 'token').write_text('disposable-test-token-not-for-real-use\n')
    (root / 'empty.yaml').write_text('{}\n')
    Path('/etc/hosts').write_text('127.0.0.1 localhost\n')
    Path('/etc/passwd').write_text('root:x:0:0:fixture:/tmp:/bin/sh\n')
    Path('/etc/group').write_text('root:x:0:\n')
    run(['ip', 'link', 'set', 'lo', 'up'])
    run(['ip', 'link', 'add', 'fixture-br', 'type', 'bridge'])
    run(['ip', 'address', 'add', '10.241.0.1/24', 'dev', 'fixture-br'])
    run(['ip', 'link', 'set', 'fixture-br', 'up'])
    processes = {}
    logs = []

    def net(name, argv, **kwargs):
        return run(['nsenter', '--net=/run/netns/' + name, *argv], **kwargs)

    def start(name, join=False, label='initial'):
        directory = root / name
        directory.mkdir(exist_ok=True)
        address = '10.241.0.' + str(10 + int(name[-1]))
        command = [args.k3s, 'server', '--config', str(root / 'empty.yaml'),
                   '--data-dir', str(directory), '--write-kubeconfig', str(directory / 'kubeconfig'),
                   '--token-file', str(root / 'token'), '--node-name', name,
                   '--node-ip', address, '--advertise-address', address,
                   '--disable-agent', '--disable-cloud-controller', '--disable-network-policy',
                   '--disable-helm-controller', '--disable-scheduler', '--egress-selector-mode=disabled',
                   '--flannel-backend=none', '--disable=coredns,servicelb,traefik,local-storage,metrics-server',
                   '--etcd-disable-snapshots', '--etcd-arg=snapshot-count=100',
                   '--etcd-arg=snapshot-catchup-entries=10']
        if name == 'cp1' and not (join and args.replace_member):
            command.append('--cluster-init')
        if join or name != 'cp1':
            command.extend(['--server', 'https://10.241.0.13:6443' if join else 'https://10.241.0.11:6443'])
        log = (root / f'{name}-{label}.log').open('w')
        logs.append(log)
        processes[name] = subprocess.Popen(['nsenter', '--net=/run/netns/' + name, *command], stdout=log, stderr=log)
        return processes[name]

    def stop(name):
        proc = processes.pop(name, None)
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)

    def etcd(name, *arguments, value=None):
        tls = root / name / 'server/tls/etcd'
        return net(name, [args.etcdctl, '--endpoints=https://127.0.0.1:2379',
                         '--cacert=' + str(tls / 'server-ca.crt'),
                         '--cert=' + str(tls / 'client.crt'), '--key=' + str(tls / 'client.key'),
                         '--dial-timeout=2s', '--command-timeout=3s', *arguments], timeout=8, input=value).stdout

    def wait_health(name, timeout=100):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            proc = processes[name]
            if proc.poll() is not None:
                raise AssertionError(f'{name} exited {proc.returncode}; inspect private fixture log')
            try:
                etcd(name, 'endpoint', 'health')
                return
            except subprocess.CalledProcessError:
                time.sleep(1)
        raise AssertionError(f'{name} did not become healthy within fixture deadline')

    def status(name):
        return json.loads(etcd(name, 'endpoint', 'status', '-w', 'json'))[0]['Status']

    try:
        for name in ('cp1', 'cp2', 'cp3'):
            run(['ip', 'netns', 'add', name])
            run(['ip', 'link', 'add', name + '-host', 'type', 'veth', 'peer', 'name', name + '-guest'])
            run(['ip', 'link', 'set', name + '-guest', 'netns', name])
            run(['ip', 'link', 'set', name + '-host', 'master', 'fixture-br'])
            run(['ip', 'link', 'set', name + '-host', 'up'])
            net(name, ['ip', 'link', 'set', 'lo', 'up'])
            net(name, ['ip', 'address', 'add', f'10.241.0.{10 + int(name[-1])}/24', 'dev', name + '-guest'])
            net(name, ['ip', 'link', 'set', name + '-guest', 'up'])
            assert 'default' not in net(name, ['ip', 'route']).stdout
            start(name)
            wait_health(name)
            print(name + ' initial healthy', flush=True)

        # Rotate and prune real 64MiB WAL segments, rather than replaying genesis.
        for index in range(450):
            etcd('cp3', 'put', '/fixture/sequence', value=str(index) + ':' + 'x' * (1024 * 1024))
            if index % 50 == 0:
                print(f'mature writes {index}/450', flush=True)
        wal = root / 'cp1/server/db/etcd/member/wal'
        end = time.monotonic() + 65
        while time.monotonic() < end:
            segments = sorted(wal.glob('*.wal'))
            if segments and int(segments[0].name.split('-')[0], 16) > 0:
                break
            time.sleep(1)
        assert segments and int(segments[0].name.split('-')[0], 16) > 0, 'pruned genesis WAL required'
        (root / 'retained-wal.json').write_text(json.dumps([p.name for p in segments]))
        initial = {name: status(name) for name in processes}
        assert all(s['version'] == '3.6.14' for s in initial.values())
        revision = initial['cp3']['header']['revision']
        initial_revision = revision
        etcd('cp3', 'compact', str(revision - 10))
        end = time.monotonic() + 30
        while not list((root / 'cp1/server/db/etcd/member/snap').glob('*.snap')) and time.monotonic() < end:
            time.sleep(1)
        assert list((root / 'cp1/server/db/etcd/member/snap').glob('*.snap')), 'mature raft snapshot required'
        (root / 'initial-identities.json').write_text(json.dumps(initial, indent=2))
        stop('cp1')
        snap = root / 'cp1/server/db/etcd/member/snap'
        assert snap.parent == root / 'cp1/server/db/etcd/member'
        assert list((snap.parent / 'wal').iterdir()), 'retained WAL required'
        shutil.rmtree(snap)  # Only synthetic fixture data inside the isolated /work mount.
        start('cp1', label='baseline')
        try:
            wait_health('cp1', timeout=45)
        except AssertionError:
            baseline = (root / 'cp1-baseline.log').read_text()
            assert 'failed to stat MVCC KV store backend path: stat /work/cp1/server/db/etcd-tmp/member/snap/db: no such file or directory' in baseline, 'exact incident baseline required'
            print('BASELINE_BOOTSTRAP_FAILURE_OBSERVED', flush=True)
        else:
            raise AssertionError('baseline unexpectedly recovered; incident not reproduced')
        finally:
            stop('cp1')
        if args.replace_member:
            # New hypothesis: remove precisely the stopped synthetic member, not a Node.
            members = json.loads(etcd('cp3', 'member', 'list', '-w', 'json'))['members']
            old_id = initial['cp1']['header']['member_id']
            old = [m for m in members if m['ID'] == old_id]
            assert len(old) == 1 and old[0]['peerURLs'] == ['https://10.241.0.11:2380']
            assert old[0]['name'].startswith('cp1-')
            for peer in ('cp2', 'cp3'):
                etcd(peer, 'endpoint', 'health')
            identity_files = [root / 'token', *(root / 'cp1/server/tls').rglob('*')]
            preserved = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in identity_files if p.is_file()}
            etcd('cp3', 'member', 'remove', format(old_id, 'x'))
            remaining = json.loads(etcd('cp3', 'member', 'list', '-w', 'json'))['members']
            assert {m['ID'] for m in remaining} == {
                initial[n]['header']['member_id'] for n in ('cp2', 'cp3')
            }
            data = root / 'cp1/server/db/etcd'
            quarantine = root / 'cp1/server/db/etcd-quarantined'
            assert data.exists() and not quarantine.exists()
            data.rename(quarantine)
            assert all(hashlib.sha256((root / n).read_bytes()).hexdigest() == h
                       for n, h in preserved.items()), 'identity files changed during quarantine'
            (root / 'replacement-boundary.json').write_text(json.dumps({
                'removed_id': old_id, 'removed_name': old[0]['name'],
                'remaining_ids': [m['ID'] for m in remaining],
                'preserved_file_hashes': preserved,
                'node_identity_limit': 'Agentless fixture has no Kubernetes Node UID/password controller.'
            }, indent=2))
            print('EXACT_STOPPED_MEMBER_REMOVED_ETCD_QUARANTINED', flush=True)
        start('cp1', join=True, label='candidate')
        wait_health('cp1', timeout=100)
        # Give storage-version monitoring time to converge after raft recovery.
        time.sleep(30)
        end = time.monotonic() + 35
        while True:
            final = {name: status(name) for name in processes}
            if all(s.get('storageVersion') == '3.6.0' for s in final.values()):
                break
            assert time.monotonic() < end, 'storage versions failed to converge'
            time.sleep(1)
        assert all(s['version'] == '3.6.14' for s in final.values())
        for name in final:
            etcd(name, 'endpoint', 'health')
            assert not json.loads(etcd(name, 'alarm', 'list', '-w', 'json')).get('alarms')
        candidate_log = (root / 'cp1-candidate.log').read_text()
        assert 'received and saved database snapshot' in candidate_log, 'peer snapshot recovery required'
        for name in final:
            for key in ('cluster_id', 'member_id'):
                if args.replace_member and name == 'cp1' and key == 'member_id':
                    assert final[name]['header'][key] != initial[name]['header'][key], 'replacement ID must be new'
                else:
                    assert final[name]['header'][key] == initial[name]['header'][key], f'{name} changed {key}'
        members = json.loads(etcd('cp3', 'member', 'list', '-w', 'json'))['members']
        assert len(members) == 3 and all(not m.get('isLearner', False) for m in members)
        assert {m['ID'] for m in members} == {s['header']['member_id'] for s in final.values()}
        revision = min(s['header']['revision'] for s in final.values())
        assert revision >= initial_revision, 'recovery must not lose the mature revision'
        hashes = {name: json.loads(etcd(name, 'endpoint', 'hashkv', '--rev=' + str(revision), '-w', 'json')) for name in final}
        assert all(value[0]['HashKV']['hash_revision'] == revision for value in hashes.values())
        assert len({value[0]['HashKV']['compact_revision'] for value in hashes.values()}) == 1
        assert len({value[0]['HashKV']['hash'] for value in hashes.values()}) == 1
        (root / 'final-identities-hashes.json').write_text(json.dumps({'status': final, 'hashes': hashes}, indent=2))
        print('REPLACEMENT_SAME_CLUSTER_SURVIVORS_NEW_MEMBER_COMMON_HASH' if args.replace_member else
              'CANDIDATE_RECOVERED_SAME_IDENTITIES_COMMON_HASH', flush=True)
    finally:
        for name in list(processes):
            stop(name)
        for log in logs:
            log.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--k3s', required=True)
    parser.add_argument('--etcdctl', required=True)
    parser.add_argument('--bwrap')
    parser.add_argument('--inside', action='store_true')
    parser.add_argument('--replace-member', action='store_true')
    parser.add_argument('--host-net')
    args = parser.parse_args()
    if args.inside:
        inside(args)
        return
    assert args.bwrap
    output = Path(tempfile.mkdtemp(prefix='k3s-bootstrap-reproduction-'))
    print('FIXTURE_RECEIPT=' + str(output), flush=True)
    command = [args.bwrap, '--unshare-all', '--uid', '0', '--gid', '0',
               '--cap-add', 'CAP_NET_ADMIN', '--cap-add', 'CAP_SYS_ADMIN',
               '--die-with-parent', '--clearenv', '--setenv', 'PATH', '/bin',
               '--setenv', 'HOME', '/tmp', '--ro-bind', '/nix/store', '/nix/store',
               '--ro-bind', '/run/current-system/sw/bin', '/bin', '--proc', '/proc', '--dev', '/dev',
               '--tmpfs', '/tmp', '--dir', '/etc', '--dir', '/var', '--dir', '/run', '--dir', '/sys',
               '--symlink', '/run', '/var/run', '--bind', str(output), '/work',
               '--ro-bind', str(Path(__file__).resolve()), '/fixture.py',
               str(Path(sys.executable).resolve()), '/fixture.py', '--inside', '--host-net', os.readlink('/proc/self/ns/net'),
               '--k3s', args.k3s, '--etcdctl', args.etcdctl]
    if args.replace_member:
        command.append('--replace-member')
    # Bound the complete disposable campaign, including bootstrap and recovery.
    result = subprocess.run(command, timeout=600)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
