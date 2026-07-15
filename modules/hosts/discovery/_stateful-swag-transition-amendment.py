#!/usr/bin/env python3
"""Amend the immutable SWAG transition journal after its render-hash halt."""
import argparse, fcntl, hashlib, importlib.util, json, os, pathlib, subprocess, sys, tempfile

HERE=pathlib.Path(__file__).resolve().parent
BASE_PATH=pathlib.Path(os.environ.get("SWAG_TRANSITION_BASE",HERE/"_stateful-swag-transition.py"))
spec=importlib.util.spec_from_file_location("swag_transition_base",BASE_PATH)
base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
REPO=base.REPOSITORY; CREDENTIAL=base.CREDENTIAL; EVIDENCE=base.EVIDENCE; LOCK=base.LOCK
OLD=EVIDENCE/"transition-b676063"; NEW=EVIDENCE/"transition-b676063-amendment"
TARGET=base.TARGET; RENDER="282e5e26ab38926d8fcdb6aad74c836089a7d72e3f2e85f172932697e6d34887"
OLD_MANIFEST="426fa097cd4b6ce0e12609e25f64732dac0f1dacfb4dda8f1a3563f3cca854e4"
OLD_AUTH="a34e064ac10a529bba3a8157cef2692cb597dee2fcf25c36c64704b1f1b17ad4"
OLD_OBSERVATION="b04c70cd83b841c28bdda82be09af92be275dfb19df03477f235c54efa68f1b2"
PHASES=["repo-target","init-complete","metadata-complete","swag-complete","validated"]
RENDER_CONTRACT={"version":1,"cwd":str(base.WORKDIR),"argv":["docker-compose","--project-name","networking","--project-directory",str(base.WORKDIR),"--env-file",str(base.WORKDIR/".env"),"--env-file","/run/vault-agent/networking.env","-f",str(base.COMPOSE),"config","--no-interpolate","--no-env-resolution"]}
ACTIONS=["persist-amendment-no-clobber-journal","verify-immutable-halted-journal","verify-target-repository-and-literal-render","recreate-exact-swag-init","set-and-verify-credential-metadata","recreate-exact-swag","validate-and-persist-result"]
Drift=base.Drift
def canonical(value): return base.canonical(value)
def envelope(value): return base.envelope(value)
def exact(value,keys,label): return base.exact(value,keys,label)

def plan(obs):
    exact(obs,{"attempt_01","attempt_02","credential","old_journal","repo","runtime"},"observation")
    # The predecessor validators are intentionally structural here; execution
    # rehashes every retained artifact before any lifecycle action.
    a1=obs["attempt_01"]; exact(a1,{"inventory_sha256","manifest_sha256","retained"},"attempt-01")
    if {k:a1[k] for k in base.PREDECESSOR}!=base.PREDECESSOR: raise Drift("attempt-01 differs")
    a2=obs["attempt_02"]; exact(a2,{"artifacts","manifest_sha256","observation_sha256","phase_markers","top_level_entries"},"attempt-02")
    if any(a2[k]!=v for k,v in base.ATTEMPT_02_BINDING.items()) or a2["phase_markers"]!=["init-complete","swag-complete"] or a2["top_level_entries"]!=["authorization.json","observation.json","phases","post-runtime.json"]: raise Drift("attempt-02 differs")
    old=obs["old_journal"]; exact(old,{"artifacts","manifest_sha256","phase_markers","top_level_entries"},"old journal")
    if old["manifest_sha256"]!=OLD_MANIFEST or old["phase_markers"]!=[] or old["top_level_entries"]!=["authorization.json","observation.json","phases"]: raise Drift("old journal shape differs")
    expected_old={"authorization":(OLD/"authorization.json",OLD_AUTH),"observation":(OLD/"observation.json",OLD_OBSERVATION)}
    exact(old["artifacts"],expected_old,"old artifacts")
    for name,(path,digest) in expected_old.items():
        if old["artifacts"][name]!={"path":str(path),"sha256":digest}: raise Drift("old journal artifact differs")
    if obs["credential"]!={"absent":True,"path":str(CREDENTIAL),"symlink":False}: raise Drift("credential absence differs")
    base.validate_runtime(obs["runtime"])
    repo=obs["repo"]; exact(repo,{"clean","head","origin_main","render_contract","render_sha256"},"repository")
    if repo!={"clean":True,"head":TARGET,"origin_main":TARGET,"render_contract":RENDER_CONTRACT,"render_sha256":RENDER}: raise Drift("target repository binding differs")
    return {"actions":ACTIONS,"approval_scope":{"compose_project":"networking","services":["swag-init","swag"]},"attempt_01":a1,"attempt_02":a2,"credential_rewrite_contract":"swag-init rewrites the absent file from runtime-vault-env; values never read, output, or bound","mode":"execute-transition-amendment","observation_sha256":hashlib.sha256(canonical(obs)).hexdigest(),"old_journal":old,"phases":PHASES,"repo":repo,"runtime":obs["runtime"],"version":1}
def verify(obs,auth):
    expected=envelope(plan(obs))
    if auth!=expected: raise Drift("observation or amendment binding differs")
    return {"manifest_sha256":expected["manifest_sha256"],"status":"binding-valid"}

def phase(name): return NEW/"phases"/name
def phases():
    entries=sorted(x.name for x in (NEW/"phases").iterdir())
    if entries!=sorted(PHASES[:len(entries)]) or any(not phase(x).is_dir() for x in entries): raise Drift("amendment phase prefix differs")
    allowed={"authorization.json","observation.json","phases","init-state.json","metadata-state.json","final-runtime.json","kindle.png","result.json"}
    if not {x.name for x in NEW.iterdir()}<=allowed: raise Drift("amendment artifact set differs")
    return set(entries)
def mark(name): phase(name).mkdir(mode=0o700); base.fsync_dir(NEW/"phases")
def runtime(): return json.loads(base.run(["discovery-stateful-swag-inventory","capture-runtime"],capture=True))
def persist_exact(path,value):
    if path.exists():
        if not base.same_json(path,value):raise Drift("amendment evidence collision")
    else:base.write_json(path,value);base.fsync_dir(NEW)
def publish(obs,auth):
    temp=pathlib.Path(tempfile.mkdtemp(prefix=".amendment.prepare.",dir=EVIDENCE))
    try:
        base.write_json(temp/"authorization.json",auth); base.write_json(temp/"observation.json",obs); (temp/"phases").mkdir(mode=0o700); base.fsync_dir(temp); base.rename_noreplace(temp,NEW); base.fsync_dir(EVIDENCE); temp=None
    finally:
        if temp:
            for name in ("authorization.json","observation.json"):
                try:(temp/name).unlink()
                except FileNotFoundError:pass
            try:(temp/"phases").rmdir();temp.rmdir()
            except OSError:pass
def verify_old(obs):
    if sorted(x.name for x in OLD.iterdir())!=obs["old_journal"]["top_level_entries"] or list((OLD/"phases").iterdir()): raise Drift("old journal changed")
    for item in obs["old_journal"]["artifacts"].values():
        if base.hash_file(item["path"])!=item["sha256"]: raise Drift("old journal hash differs")
    old_auth=base.read_json(OLD/"authorization.json")
    if old_auth.get("manifest_sha256")!=OLD_MANIFEST: raise Drift("old journal manifest differs")
    base.revalidate_predecessor_evidence(obs)
def render_sha():
    completed=subprocess.run(RENDER_CONTRACT["argv"],cwd=RENDER_CONTRACT["cwd"],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    return hashlib.sha256(completed.stdout).hexdigest()
def verify_repo(obs):
    if base.git_run(["rev-parse","HEAD"],capture=True).strip()!=TARGET or base.git_run(["rev-parse","origin/main"],capture=True).strip()!=TARGET or base.git_run(["status","--porcelain","--untracked-files=no"],capture=True).strip() or render_sha()!=RENDER: raise Drift("live target repository differs")
def observe():
    entries=sorted(x.name for x in OLD.iterdir());markers=sorted(x.name for x in (OLD/"phases").iterdir())
    old_auth=base.read_json(OLD/"authorization.json"); manifest=old_auth["manifest"]
    try:os.lstat(CREDENTIAL)
    except FileNotFoundError:pass
    else:raise Drift("credential path is not absent")
    return {"attempt_01":manifest["attempt_01"],"attempt_02":manifest["attempt_02"],"credential":{"absent":True,"path":str(CREDENTIAL),"symlink":False},"old_journal":{"artifacts":{"authorization":{"path":str(OLD/"authorization.json"),"sha256":base.hash_file(OLD/"authorization.json")},"observation":{"path":str(OLD/"observation.json"),"sha256":base.hash_file(OLD/"observation.json")}},"manifest_sha256":old_auth["manifest_sha256"],"phase_markers":markers,"top_level_entries":entries},"repo":{"clean":not bool(base.git_run(["status","--porcelain","--untracked-files=no"],capture=True).strip()),"head":base.git_run(["rev-parse","HEAD"],capture=True).strip(),"origin_main":base.git_run(["rev-parse","origin/main"],capture=True).strip(),"render_contract":RENDER_CONTRACT,"render_sha256":render_sha()},"runtime":runtime()}

def execute(obs,auth,approved):
    if verify(obs,auth)["manifest_sha256"]!=approved: raise Drift("approved amendment differs")
    fd=os.open(LOCK,os.O_WRONLY|os.O_CLOEXEC|os.O_NOFOLLOW)
    try:
        fcntl.flock(fd,fcntl.LOCK_EX); verify_old(obs)
        if not NEW.exists(): publish(obs,auth)
        elif not base.same_json(NEW/"authorization.json",auth) or not base.same_json(NEW/"observation.json",obs): raise Drift("amendment journal collision")
        done=phases()
        if "validated" in done:return validate_completed(obs,approved)
        verify_repo(obs)
        if "repo-target" not in done:
            try:os.lstat(CREDENTIAL)
            except FileNotFoundError:pass
            else:raise Drift("credential is not absent")
            if runtime()!=obs["runtime"]:raise Drift("authorized runtime differs")
            mark("repo-target");done.add("repo-target")
        compose=["docker-compose","--project-name","networking","--env-file",str(base.WORKDIR/".env"),"--env-file","/run/vault-agent/networking.env","-f",str(base.COMPOSE)]
        pre={x["name"]:x for x in obs["runtime"]["containers"]}
        if "init-complete" not in done:
            now=runtime()
            try:meta=base.metadata()
            except FileNotFoundError:
                if now!=obs["runtime"]:raise Drift("pre-init runtime differs")
                base.run(compose+["up","--no-deps","--force-recreate","--abort-on-container-exit","--exit-code-from","swag-init","swag-init"]);now=runtime();meta=base.metadata()
            base.validate_generated_metadata(meta);by={x["name"]:x for x in now["containers"]}
            if by["swag"]["id"]!=pre["swag"]["id"] or by["swag-init"]["id"]==pre["swag-init"]["id"]:raise Drift("init identity transition differs")
            state={"credential":meta,"runtime":now}
            if (NEW/"init-state.json").exists() and not base.same_json(NEW/"init-state.json",state):raise Drift("init state collision")
            if not (NEW/"init-state.json").exists():base.write_json(NEW/"init-state.json",state);base.fsync_dir(NEW)
            mark("init-complete");done.add("init-complete")
        init=base.read_json(NEW/"init-state.json")
        if "metadata-complete" not in done:
            if runtime()!=init["runtime"]:raise Drift("recorded init runtime differs before metadata")
            base.repair_metadata(init["credential"]);meta=base.metadata();persist_exact(NEW/"metadata-state.json",meta);mark("metadata-complete");done.add("metadata-complete")
        if base.metadata()!=base.read_json(NEW/"metadata-state.json"):raise Drift("metadata state differs")
        if "swag-complete" not in done:
            now=runtime();by={x["name"]:x for x in now["containers"]}
            if by["swag"]["id"]==pre["swag"]["id"]:base.run(compose+["up","-d","--no-deps","--force-recreate","swag"]);now=runtime();by={x["name"]:x for x in now["containers"]}
            base.validate_runtime(now)
            if any(by[n]["id"]==pre[n]["id"] for n in ("swag-init","swag")):raise Drift("both container identities must change")
            persist_exact(NEW/"final-runtime.json",now);mark("swag-complete");done.add("swag-complete")
        final=base.read_json(NEW/"final-runtime.json")
        if runtime()!=final:raise Drift("final runtime differs")
        png=base.validate_gates()
        if not (NEW/"kindle.png").exists():base.write_bytes(NEW/"kindle.png",png)
        else:
            with open(NEW/"kindle.png","rb") as stream:
                if stream.read(8)!=b"\x89PNG\r\n\x1a\n":raise Drift("stored PNG differs")
        result={"corrected_render_contract":RENDER_CONTRACT,"corrected_render_sha256":RENDER,"kindle_png_sha256":base.hash_file(NEW/"kindle.png"),"manifest_sha256":approved,"resume_origin":"post-reset-pre-phase","runtime_sha256":hashlib.sha256(canonical(final)).hexdigest(),"status":"passed","supersedes_manifest_sha256":OLD_MANIFEST,"version":1}
        persist_exact(NEW/"result.json",result);mark("validated");base.fsync_dir(EVIDENCE);return result
    finally:os.close(fd)
def validate_completed(obs,approved):
    verify_repo(obs); final=base.read_json(NEW/"final-runtime.json")
    base.validate_runtime(final)
    if runtime()!=final:raise Drift("completed runtime differs")
    pre={x["name"]:x["id"] for x in obs["runtime"]["containers"]};post={x["name"]:x["id"] for x in final["containers"]}
    if any(pre[name]==post[name] for name in ("swag-init","swag")):raise Drift("completed container identities differ")
    meta=base.read_json(NEW/"metadata-state.json")
    if base.metadata()!=meta or (meta["uid"],meta["gid"],meta["mode"])!=(1000,1000,"0600"):raise Drift("completed credential metadata differs")
    result=base.read_json(NEW/"result.json")
    with open(NEW/"kindle.png","rb") as stream:
        if stream.read(8)!=b"\x89PNG\r\n\x1a\n":raise Drift("completed PNG differs")
    if result!={"corrected_render_contract":RENDER_CONTRACT,"corrected_render_sha256":RENDER,"kindle_png_sha256":base.hash_file(NEW/"kindle.png"),"manifest_sha256":approved,"resume_origin":"post-reset-pre-phase","runtime_sha256":hashlib.sha256(canonical(final)).hexdigest(),"status":"passed","supersedes_manifest_sha256":OLD_MANIFEST,"version":1}:raise Drift("completed result differs")
    base.validate_gates();return result
def read(path):
    with open(path,encoding="utf-8") as stream:return json.load(stream)
def main(argv=None):
    p=argparse.ArgumentParser();s=p.add_subparsers(dest="cmd",required=True)
    for name in ("plan","verify","execute"):
        q=s.add_parser(name);q.add_argument("observation")
        if name!="plan":q.add_argument("authorization")
        if name=="execute":q.add_argument("--manifest-sha",required=True)
    s.add_parser("observe")
    a=p.parse_args(argv)
    try:
        if a.cmd=="observe":result=observe()
        else:
            obs=read(a.observation);result=envelope(plan(obs)) if a.cmd=="plan" else verify(obs,read(a.authorization)) if a.cmd=="verify" else execute(obs,read(a.authorization),a.manifest_sha)
    except (Drift,OSError,subprocess.SubprocessError,json.JSONDecodeError) as error:print(f"stateful-swag-transition-amendment: BLOCKED: {error}",file=sys.stderr);return 1
    print(json.dumps(result,sort_keys=True,separators=(",",":")));return 0
if __name__=="__main__":raise SystemExit(main())
