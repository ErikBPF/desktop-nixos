"""Execute the actual drill body with synthetic external services."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
SNAP = '/var/lib/vault-snapshots/openbao.snap'
ID = 'a' * 64
FAKE = r'''import json, os, sys, time
from pathlib import Path
cmd=Path(sys.argv[0]).name
args=sys.argv[1:]
p=Path(os.environ['CASE_ROOT']); mode=os.environ['CASE_MODE']
with (p/'calls').open('a') as f: f.write(json.dumps([cmd]+args)+'\n')
if cmd=='date': print(2000000000)
elif cmd=='ss':
 if mode=='occupied': print('LISTEN 0 128 127.0.0.1:18200')
elif cmd=='restic':
 if mode=='unavailable': print('synthetic-secret',file=sys.stderr); sys.exit(1)
 if args[0]=='snapshots':
  v=[{'id':'a'*64}]
  if mode=='empty': v=[]
  if mode=='ambiguous': v*=2
  if mode=='badid': v=[{'id':'latest'}]
  print(json.dumps(v))
 elif args[0]=='ls':
  age={'stale':172801,'boundary':172800,'future':-1}.get(mode,60)
  import datetime
  node={'struct_type':'node','path':'/var/lib/vault-snapshots/openbao.snap','type':'file','size':10,'mtime':datetime.datetime.fromtimestamp(2000000000-age,datetime.timezone.utc).isoformat()}
  if mode=='wrongpath': node['path']='/other'
  if mode=='symlink': node['type']='symlink'
  if mode=='zero': node['size']=0
  if mode=='badtime': node['mtime']='garbage'
  print(json.dumps(node))
 elif args[0]=='dump':
  print('synthetic-raft')
  if mode=='partial': sys.exit(1)
elif cmd=='bao':
 if args[0]=='server':
  (p/'pid').write_text(str(os.getpid()))
  if mode=='dead': sys.exit(1)
  time.sleep(120)
 elif args[1]=='init': print('{"unseal_keys_b64":["synthetic-secret"],"root_token":"synthetic-secret"}')
 elif 'restore' in args and mode=='restore': sys.exit(1)
elif cmd=='curl':
 url=args[-1]
 if url.endswith('/health'):
  time.sleep(.02)
 elif url.endswith('/unseal'):
  if mode=='unseal': sys.exit(1)
 elif url.endswith('/seal-status'): print('{"initialized":true,"sealed":false}')
 elif url.endswith('/login'):
  if mode=='auth': sys.exit(1)
  print('{"auth":{"client_token":"synthetic-secret"}}')
'''

class RestoreTest(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory); (p/'bin').mkdir(); (p/'scratch').mkdir(); (p/'metrics').mkdir()
            metric=p/'metrics/openbao_restore_drill.prom'; metric.write_text('previous\n')
            for command in ['restic','bao','curl','ss','date']:
                f=p/'bin'/command; f.write_text('#!'+shutil.which('python3')+'\n'+FAKE); f.chmod(0o755)
            for key in ['vault_unseal_key','vault_agent_role_id','vault_agent_secret_id']:
                (p/key).write_text('synthetic-secret')
            (p/'local.snap').write_text('local-fallback-forbidden')
            source=(ROOT/'modules/hosts/discovery/vault.nix').read_text()
            script=source.split('writeShellScript "openbao-restore-drill" \'\'',1)[1].split("        '';",1)[0]
            script=textwrap.dedent(script)
            script=re.sub(r'\$\{pkgs\.[^}]+\}/bin/', '', script)
            script=script.replace('${bao}','bao').replace('${curl}','curl').replace('${jq}',shutil.which('jq'))
            script=script.replace('${snapFile}',str(p/'local.snap')).replace('${textfileDir}',str(p/'metrics'))
            # The archive path stays the production path; only the old local input is substituted.
            script=script.replace('/var/tmp/openbao-restore-drill.',str(p/'scratch/drill.')).replace('/run/secrets/',str(p)+'/').replace("''${",'${')
            env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'],CASE_ROOT=str(p),CASE_MODE=mode)
            result=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True,timeout=15)
            self.assertTrue((p/'calls').exists(), result.stderr)
            calls=[json.loads(x) for x in (p/'calls').read_text().splitlines()]
            self.assertNotIn('synthetic-secret',result.stdout+result.stderr)
            self.assertEqual(list((p/'scratch').iterdir()),[])
            if (p/'pid').exists():
                with self.assertRaises(ProcessLookupError): os.kill(int((p/'pid').read_text()),0)
            if mode=='ok':
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(['restic','dump',ID,SNAP],calls)
                self.assertIn(ID,result.stdout)
                self.assertIn('voyager',result.stdout)
                self.assertIn('openbao_restore_drill_source_timestamp_seconds 1999999940',metric.read_text())
            else:
                self.assertNotEqual(result.returncode,0,mode)
                self.assertEqual(metric.read_text(),'previous\n')
                if mode not in ['restore','unseal','auth']:
                    self.assertFalse(any(c[:3]==['bao','operator','init'] for c in calls))

    def test_remote_success(self): self.run_case('ok')
    def test_fail_closed(self):
        for mode in ['unavailable','empty','ambiguous','badid','wrongpath','symlink','zero','badtime','stale','boundary','future','partial','restore','unseal','auth','occupied','dead']:
            with self.subTest(mode=mode): self.run_case(mode)

if __name__=='__main__': unittest.main()
