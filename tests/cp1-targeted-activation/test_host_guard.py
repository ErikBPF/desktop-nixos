import json
import importlib.util
import os
from pathlib import Path
import subprocess

import pytest

SPEC = importlib.util.spec_from_file_location("cp1_manifest_fixture", Path(__file__).with_name("test_manifest.py"))
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)
metadata = FIXTURE.metadata

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/activate-cp1.sh'
PREFLIGHT = SCRIPT.read_text().split('known=$(get .knownHosts)',1)[0]


@pytest.mark.parametrize('drift', ['', 'hostCurrent', 'hostProfile', 'runner'])
def test_actual_host_paths_compare_and_abort(tmp_path,drift):
    data=metadata();data['candidate']['toplevel']='/nix/store/'+'b'*32+'-candidate'
    manifest=tmp_path/'manifest.json';manifest.write_text(json.dumps(data))
    commands=tmp_path/'bin';commands.mkdir()
    (commands/'hostname').write_text('#!/bin/sh\necho kepler\n');(commands/'hostname').chmod(0o755)
    readlink='''#!/usr/bin/env python3
import json,os,sys
m=json.loads(os.environ['EXPECTED'])
k={'/run/current-system':'hostCurrent','/nix/var/nix/profiles/system':'hostProfile','/fast/microvms/cp-1/current':'runner'}[sys.argv[2]]
print('changed' if os.environ['DRIFT']==k else m['baseline'][k])
'''
    (commands/'readlink').write_text(readlink);(commands/'readlink').chmod(0o755)
    result=subprocess.run(['bash','-se','--',str(manifest),'preview'],input=PREFLIGHT,text=True,
        env=dict(os.environ,PATH=str(commands)+':'+os.environ['PATH'],EXPECTED=json.dumps(data),DRIFT=drift),capture_output=True,timeout=5)
    assert (result.returncode == 0) == (drift == '')
