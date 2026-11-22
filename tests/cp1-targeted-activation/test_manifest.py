"""Run the owner script's real jq guard, without SSH or activation."""
import copy
import json
from pathlib import Path
import subprocess

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/activate-cp1.sh'
GUARD = SCRIPT.read_text().split("jq -e '\n",1)[1].split("\n' \"$manifest\"",1)[0]


def metadata():
    store = '/nix/store/' + 'a'*32 + '-fixture'
    hardware = {'kernel':store+'/kernel','initrd':store+'/initrd',
                'interfaces':[{'id':'vm-k3s-cp-1'}], 'volumes':[{'image':'root.img'}],
                'shares':[{'source':'/nix/store'}]}
    return {'sourceRevision':'a'*40,'knownHostsSha256':'b'*64,
            'baseline':dict(hardware=hardware,hostCurrent=store,hostProfile=store,
                guestCurrent=store,guestProfile=store,runner=store,
                guestBootId='00000000-0000-0000-0000-000000000000', bootstrapTimerState='enabled', bootstrapServiceState='enabled'),
            'candidate':dict(hardware=copy.deepcopy(hardware),toplevel=store,runner=store,
                nix=store,conditionSystemd=store,stateDir="/fast/microvms",registration=store+'/registration',clusterInit=False,
                serverAddr='https://10.250.0.13:6443',restart='no',timeoutStartSec=300,
                bootstrapTimer=False,bootstrapService=False)}


def accepts(data):
    return subprocess.run(['jq','-e',GUARD],input=json.dumps(data),text=True,
                          stdout=subprocess.DEVNULL,stderr=subprocess.PIPE).returncode == 0


def test_reviewed_manifest_passes():
    assert accepts(metadata())


@pytest.mark.parametrize('field', ['kernel','initrd','interfaces','volumes','shares'])
def test_hardware_change_rejected(field):
    data=metadata();data['candidate']['hardware'][field]='changed'
    assert not accepts(data)


@pytest.mark.parametrize(('field','value'), [('stateDir','/var/lib/microvms'),('clusterInit',True),('restart','always'),
    ('serverAddr','https://10.250.0.12:6443'),('timeoutStartSec',0),('timeoutStartSec',600),
    ('bootstrapTimer',True),('bootstrapService',True),
    ('registration','/nix/store/'+'a'*32+'-fixture/../../etc/passwd')])
def test_unsafe_candidate_rejected(field,value):
    data=metadata();data['candidate'][field]=value
    assert not accepts(data)


def test_explicit_absent_guest_profile_passes():
    data=metadata();data['baseline']['guestProfile']='absent'
    assert accepts(data)

def test_absence_cannot_replace_host_profile():
    data=metadata();data['baseline']['hostProfile']='absent'
    assert not accepts(data)
