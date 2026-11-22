"""Execute the exact built-unit comparison from the owner script."""
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/activate-cp1.sh'
CHECK = SCRIPT.read_text().split("<<'PY'\n",1)[1].split('\nPY\n',1)[0]
SYSTEMD = '/nix/store/'+'a'*32+'-systemd-262'
CONDITION_SYSTEMD = '/nix/store/'+'b'*32+'-systemd-262'


def units(tmp_path, mutation=''):
    old=tmp_path/'old';new=tmp_path/'new'
    for directory in (old,new): (directory/'etc/systemd/system').mkdir(parents=True)
    old_k3s='[Service]\nExecStart=/nix/store/k3s/bin/k3s server \\\n --cluster-init \\\n --token-file=/tokens/token\nRestart=always\nTimeoutStartSec=0\n'
    new_k3s=old_k3s.replace('--cluster-init','--server https://10.250.0.13:6443').replace('Restart=always','Restart=no').replace('TimeoutStartSec=0','TimeoutStartSec=5min')
    before='[Unit]\nAfter=k3s.service\nWants=k3s.service\n[Service]\nEnvironment="PATH='+SYSTEMD+'/bin"\nExecStart=/nix/store/fixture/reconcile\nRemainAfterExit=true\n'
    after=before.replace('Wants=k3s.service\n','').replace('[Service]\n','[Service]\nExecCondition='+CONDITION_SYSTEMD+'/bin/systemctl is-active --quiet k3s.service\n')
    if mutation=='command': after=after.replace('/fixture/reconcile','/fixture/other')
    if mutation=='condition': after=after.replace('is-active --quiet','start')
    for directory,k3s,manifest in ((old,old_k3s,before),(new,new_k3s,after)):
        (directory/'etc/systemd/system/k3s.service').write_text(k3s)
        (directory/'etc/systemd/system/k3s-manifest-reconcile.service').write_text(manifest)
    return subprocess.run([sys.executable,'-',str(old),str(new),'300',CONDITION_SYSTEMD],input=CHECK,text=True,capture_output=True)


def test_exact_reviewed_manifest_delta_allowed(tmp_path):
    result=units(tmp_path)
    assert result.returncode == 0, result.stderr


def test_unrelated_reconcile_command_rejected(tmp_path):
    assert units(tmp_path,'command').returncode != 0


def test_condition_cannot_start_k3s(tmp_path):
    assert units(tmp_path,'condition').returncode != 0
