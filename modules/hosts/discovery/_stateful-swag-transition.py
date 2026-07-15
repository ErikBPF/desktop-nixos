#!/usr/bin/env python3
"""Hash-bound SWAG repository/credential transition without secret reads."""

import argparse
import ctypes
import fcntl
import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile

REPOSITORY = pathlib.Path("/home/erik/servarr")
WORKDIR = REPOSITORY / "machines/discovery"
COMPOSE = WORKDIR / "networking.yml"
CREDENTIAL = WORKDIR / "config/swag/dns-conf/cloudflare.ini"
EVIDENCE = pathlib.Path("/var/lib/stateful-stack-migrations/p1-swag")
ATTEMPT_02 = EVIDENCE / "attempt-02"
TRANSITION = EVIDENCE / "transition-b676063"
LOCK = pathlib.Path("/run/lock/servarr-repository.lock")
CURRENT = "701c0efc23c5b0cc3fb152dd00f21dcb9a72cfc1"
TARGET = "b676063eafa53c00947c458d631493f98349f63c"
PREDECESSOR = {"inventory_sha256": "35c294e9fe74e8b824df7aa8161693bfd555f09b97d1ef36b58a280d08d521e7", "manifest_sha256": "ee7861b9789f08a6fb0319ba931760054625d3e1cabe03bf43443560db3daee7"}
ATTEMPT_02_BINDING = {"manifest_sha256": "d8317282ce3f4716491c0c6a33c354c6dea12d4a02880cc8e3d6650bf3383fad", "observation_sha256": "c1696360b1feb06ddc02059605912a3d2ea2ec6f2fc3f8d7b9d2330eba9db303"}
IMAGES = {"swag": "lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d", "swag-init": "busybox:1.38@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d"}
ACTIONS = [
    "lock-and-revalidate-current-binding",
    "persist-no-clobber-authorization-observation-journal",
    "fetch-and-verify-origin-main-at-exact-target",
    "reset-servarr-to-exact-target",
    "verify-target-value-free-compose-render",
    "require-retired-tracked-credential-path-absent",
    "recreate-exact-swag-init",
    "set-and-verify-new-credential-inode-0600-1000-1000",
    "recreate-exact-swag",
    "validate-runtime-health-certificate-and-routes",
    "atomically-persist-transition-evidence",
]
PHASES = ["repo-target", "init-complete", "metadata-complete", "swag-complete", "validated"]
STATE_MACHINE = {
    "repo-target": "target HEAD/render; credential absent; authorized pre-runtime",
    "init-complete": "target HEAD/render; generated regular credential; swag unchanged; swag-init identity changed",
    "metadata-complete": "same generated inode at 0600/1000:1000; swag unchanged",
    "swag-complete": "exact recorded runtime; both authorized container identities changed",
    "validated": "all stored evidence identities and live health/certificate/routes revalidated without mutation",
}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class Drift(ValueError): pass


def canonical(value): return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
def envelope(manifest): return {"manifest": manifest, "manifest_sha256": hashlib.sha256(canonical(manifest)).hexdigest()}


def exact(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys): raise Drift(f"{label} fields differ")


def validate_runtime(runtime):
    exact(runtime, {"containers"}, "runtime")
    items = runtime["containers"]
    if not isinstance(items, list) or len(items) != 2 or {x.get("name") for x in items} != set(IMAGES): raise Drift("runtime allowlist differs")
    expected_mount = [{"source": str(WORKDIR / "config/swag"), "target": "/config", "type": "bind"}]
    for item in items:
        exact(item, {"compose_project", "compose_service", "compose_working_dir", "id", "image_id", "image_ref", "mounts", "name", "state"}, item.get("name", "container"))
        name=item["name"]
        if item["compose_project"] != "networking" or item["compose_service"] != name or item["compose_working_dir"] != str(WORKDIR): raise Drift("Compose ownership differs")
        if item["image_ref"] != IMAGES[name] or not HEX64.fullmatch(item["id"]) or not re.fullmatch(r"sha256:[0-9a-f]{64}", item["image_id"]): raise Drift("runtime image or identity differs")
        if item["mounts"] != expected_mount or item["state"] != ("running" if name == "swag" else "exited"): raise Drift("runtime state or mount differs")


def plan(observation):
    exact(observation, {"attempt_01", "attempt_02", "credential", "runtime", "servarr"}, "observation")
    a1=observation["attempt_01"]
    exact(a1, {"inventory_sha256", "manifest_sha256", "retained"}, "attempt-01")
    if {k:a1[k] for k in PREDECESSOR} != PREDECESSOR: raise Drift("attempt-01 binding differs")
    retained_paths={"approved_inventory": EVIDENCE/"approved-inventory.json", "archive": EVIDENCE/"swag-config.tar.zst", "archive_checksum": EVIDENCE/"swag-config.tar.zst.sha256", "authorization": EVIDENCE/"authorization.json", "ledger": EVIDENCE/"ledger.json", "snapshot": pathlib.Path("/home/.snapshots/stateful-stack-p1-swag")}
    exact(a1["retained"], retained_paths, "attempt-01 retained")
    for name,path in retained_paths.items():
        item=a1["retained"][name]; identity="uuid" if name=="snapshot" else "sha256"
        exact(item, {"path",identity}, f"retained {name}")
        valid=UUID.fullmatch(item[identity]) if identity=="uuid" else HEX64.fullmatch(item[identity])
        if item["path"] != str(path) or not valid: raise Drift(f"retained {name} differs")
    a2=observation["attempt_02"]
    exact(a2, {"artifacts", "manifest_sha256", "observation_sha256", "phase_markers", "top_level_entries"}, "attempt-02")
    if any(a2[k] != v for k,v in ATTEMPT_02_BINDING.items()) or a2["phase_markers"] != ["init-complete","swag-complete"] or a2["top_level_entries"] != ["authorization.json","observation.json","phases","post-runtime.json"]: raise Drift("attempt-02 shape differs")
    artifact_files={"authorization":"authorization.json","observation":"observation.json","post_runtime":"post-runtime.json"}
    exact(a2["artifacts"], artifact_files, "attempt-02 artifacts")
    for name,file in artifact_files.items():
        item=a2["artifacts"][name]; exact(item,{"path","sha256"},f"attempt-02 {name}")
        if item["path"] != str(ATTEMPT_02/file) or not HEX64.fullmatch(item["sha256"]): raise Drift(f"attempt-02 {name} differs")
    credential=observation["credential"]
    exact(credential, {"device","gid","inode","mode","path","regular","symlink","uid"}, "credential metadata")
    if credential != {"device":credential["device"],"inode":credential["inode"],"gid":100,"mode":"0644","path":str(CREDENTIAL),"regular":True,"symlink":False,"uid":1000} or not all(isinstance(credential[k],int) and credential[k]>=0 for k in ("device","inode")): raise Drift("credential metadata differs")
    validate_runtime(observation["runtime"])
    servarr=observation["servarr"]
    exact(servarr,{"commit","compose_file","render_sha256","target_commit","target_render_sha256"},"Servarr")
    if servarr["commit"] != CURRENT or servarr["target_commit"] != TARGET or servarr["compose_file"] != str(COMPOSE) or not HEX64.fullmatch(servarr["render_sha256"]) or not HEX64.fullmatch(servarr["target_render_sha256"]): raise Drift("Servarr binding differs")
    return {"actions":ACTIONS,"approval_scope":{"compose_project":"networking","services":["swag-init","swag"]},"attempt_01":a1,"attempt_02":a2,"credential":{"current":credential,"source_contract":"rewritten-by-swag-init-from-runtime-vault-env; values-never-read-output-or-bound","target":{"gid":1000,"mode":"0600","path":str(CREDENTIAL),"regular":True,"symlink":False,"uid":1000}},"mode":"execute-exact-transition","observation_sha256":hashlib.sha256(canonical(observation)).hexdigest(),"phases":PHASES,"runtime":observation["runtime"],"state_machine":STATE_MACHINE,"servarr":servarr,"version":2}


def verify(observation, authorization):
    expected=envelope(plan(observation))
    if authorization != expected: raise Drift("observation or manifest binding differs")
    return {"manifest_sha256":expected["manifest_sha256"],"status":"binding-valid"}


def run(args, *, capture=False):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE if capture else subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True).stdout if capture else None


def render_sha():
    command=["docker-compose","--project-name","networking","--env-file",str(WORKDIR/".env"),"--env-file","/run/vault-agent/networking.env","-f",str(COMPOSE),"config","--no-interpolate","--no-env-resolution"]
    completed=subprocess.run(command,check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    return hashlib.sha256(completed.stdout).hexdigest()


def metadata(path=CREDENTIAL):
    value=os.lstat(path)
    return {"device":value.st_dev,"gid":value.st_gid,"inode":value.st_ino,"mode":f"{stat.S_IMODE(value.st_mode):04o}","path":str(path),"regular":stat.S_ISREG(value.st_mode),"symlink":stat.S_ISLNK(value.st_mode),"uid":value.st_uid}


def validate_generated_metadata(value):
    exact(value,{"device","gid","inode","mode","path","regular","symlink","uid"},"generated credential metadata")
    identity=(value["uid"],value["gid"],value["mode"])
    if value["path"]!=str(CREDENTIAL) or not value["regular"] or value["symlink"] or identity not in {(1000,100,"0644"),(1000,1000,"0600")} or not all(isinstance(value[key],int) and value[key]>=0 for key in ("device","inode")): raise Drift("generated credential intermediate state differs")


def hash_file(path):
    digest=hashlib.sha256()
    with open(path,"rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""): digest.update(block)
    return digest.hexdigest()


def repair_metadata(expected):
    flags=os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    fd=os.open(CREDENTIAL,flags)
    try:
        before=os.fstat(fd)
        if (before.st_dev,before.st_ino)!=(expected["device"],expected["inode"]) or not stat.S_ISREG(before.st_mode): raise Drift("credential inode changed")
        os.fchown(fd,1000,1000); os.fchmod(fd,0o600); os.fsync(fd)
        after=os.fstat(fd)
        path_now=os.lstat(CREDENTIAL)
        if (after.st_dev,after.st_ino)!=(path_now.st_dev,path_now.st_ino) or stat.S_IMODE(after.st_mode)!=0o600 or (after.st_uid,after.st_gid)!=(1000,1000): raise Drift("credential target metadata differs")
    finally: os.close(fd)


def revalidate_predecessor_evidence(observation):
    for item in observation["attempt_01"]["retained"].values():
        if "sha256" in item and hash_file(item["path"]) != item["sha256"]: raise Drift("attempt-01 evidence differs")
    entries=sorted(path.name for path in ATTEMPT_02.iterdir())
    if entries != observation["attempt_02"]["top_level_entries"]: raise Drift("attempt-02 top-level entries differ")
    phases=sorted(path.name for path in (ATTEMPT_02/"phases").iterdir())
    if phases != observation["attempt_02"]["phase_markers"]: raise Drift("attempt-02 phases differ")
    for item in observation["attempt_02"]["artifacts"].values():
        if hash_file(item["path"]) != item["sha256"]: raise Drift("attempt-02 evidence differs")
    run(["discovery-stateful-swag-preflight","resume-verify",str(ATTEMPT_02/"observation.json"),str(ATTEMPT_02/"authorization.json")])
    snapshot_output=run(["btrfs","subvolume","show",observation["attempt_01"]["retained"]["snapshot"]["path"]],capture=True)
    snapshot_uuid=next((line.split()[-1] for line in snapshot_output.splitlines() if line.strip().startswith("UUID:")),"")
    if snapshot_uuid != observation["attempt_01"]["retained"]["snapshot"]["uuid"]: raise Drift("attempt-01 snapshot differs")


def runtime_validation_phase(phases):
    """Select the only runtime identity valid for a monotonic phase prefix."""
    if "swag-complete" in phases or "validated" in phases: return "final"
    if "init-complete" in phases or "metadata-complete" in phases: return "init"
    return "pre"


RENAME_NOREPLACE=1
def rename_noreplace(source,target):
    libc=ctypes.CDLL(None,use_errno=True)
    result=libc.renameat2(-100,os.fsencode(source),-100,os.fsencode(target),RENAME_NOREPLACE)
    if result != 0: raise OSError(ctypes.get_errno(),"atomic evidence publish failed")


def write_json(path,value):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_CLOEXEC,0o400)
    payload=canonical(value)+b"\n"
    try:
        view=memoryview(payload)
        while view: view=view[os.write(fd,view):]
        os.fsync(fd)
    finally: os.close(fd)
    if hash_file(path) != hashlib.sha256(payload).hexdigest(): raise OSError("evidence write verification failed")


def write_bytes(path,value):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_CLOEXEC,0o400)
    try:
        view=memoryview(value)
        while view: view=view[os.write(fd,view):]
        os.fsync(fd)
    finally: os.close(fd)
    if hash_file(path) != hashlib.sha256(value).hexdigest(): raise OSError("evidence write verification failed")


def fsync_dir(path):
    fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
    try: os.fsync(fd)
    finally: os.close(fd)


def phase_path(name): return TRANSITION/"phases"/name


def mark_phase(name):
    if name not in PHASES: raise Drift("unknown transition phase")
    index=PHASES.index(name)
    if any(not phase_path(previous).is_dir() for previous in PHASES[:index]): raise Drift("transition phase order differs")
    phase_path(name).mkdir(mode=0o700)
    fsync_dir(TRANSITION/"phases")


def exact_phase_prefix():
    if not (TRANSITION/"phases").is_dir(): raise Drift("transition phase journal absent")
    entries=sorted(path.name for path in (TRANSITION/"phases").iterdir())
    if any(not (TRANSITION/"phases"/name).is_dir() for name in entries): raise Drift("transition phase entry differs")
    if entries != sorted(PHASES[:len(entries)]): raise Drift("transition phase prefix differs")
    present={path.name for path in TRANSITION.iterdir()}
    base={"authorization.json","observation.json","phases"}
    allowed=base|{"init-state.json","metadata-state.json","final-runtime.json","kindle.png","result.json"}
    if not base <= present or not present <= allowed: raise Drift("transition artifact set differs")
    required=set(base)
    if "init-complete" in entries: required.add("init-state.json")
    if "metadata-complete" in entries: required.add("metadata-state.json")
    if "swag-complete" in entries: required.add("final-runtime.json")
    if "validated" in entries: required.update({"kindle.png","result.json"})
    if not required <= present: raise Drift("transition phase artifact absent")
    latest=PHASES[len(entries)-1] if entries else None
    prepared={None:set(),"repo-target":{"init-state.json"},"init-complete":{"metadata-state.json"},"metadata-complete":{"final-runtime.json"},"swag-complete":{"kindle.png","result.json"},"validated":set()}
    if not (present-required) <= prepared[latest]: raise Drift("transition artifact is ahead of phase journal")
    return set(entries)


def publish_journal(observation,authorization):
    temporary=pathlib.Path(tempfile.mkdtemp(prefix=".transition.prepare.",dir=EVIDENCE))
    try:
        write_json(temporary/"authorization.json",authorization)
        write_json(temporary/"observation.json",observation)
        (temporary/"phases").mkdir(mode=0o700)
        fsync_dir(temporary/"phases"); fsync_dir(temporary)
        rename_noreplace(temporary,TRANSITION)
        fsync_dir(EVIDENCE)
        temporary=None
    finally:
        if temporary is not None:
            for name in ("authorization.json","observation.json"):
                try: (temporary/name).unlink()
                except FileNotFoundError: pass
            try: (temporary/"phases").rmdir()
            except OSError: pass
            try: temporary.rmdir()
            except OSError: pass


def same_json(path,value):
    return read_json(path)==value


def current_runtime(): return json.loads(run(["discovery-stateful-swag-inventory","capture-runtime"],capture=True))


def execute(observation,authorization,expected_sha):
    verified=verify(observation,authorization)
    if verified["manifest_sha256"] != expected_sha: raise Drift("approved manifest differs")
    lock_fd=os.open(LOCK,os.O_WRONLY|os.O_CLOEXEC|os.O_NOFOLLOW)
    try:
        fcntl.flock(lock_fd,fcntl.LOCK_EX)
        revalidate_predecessor_evidence(observation)
        if not TRANSITION.exists():
            if run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip()!=CURRENT or render_sha()!=observation["servarr"]["render_sha256"] or metadata()!=observation["credential"] or current_runtime()!=observation["runtime"]: raise Drift("fresh authorized pre-state differs")
            if run(["git","-C",str(REPOSITORY),"status","--porcelain","--untracked-files=no"],capture=True).strip(): raise Drift("tracked Servarr worktree is dirty")
            publish_journal(observation,authorization)
        else:
            if not TRANSITION.is_dir() or not same_json(TRANSITION/"authorization.json",authorization) or not same_json(TRANSITION/"observation.json",observation): raise Drift("transition journal collision")
        phases=exact_phase_prefix()
        if "validated" in phases:
            return validate_completed(expected_sha,authorization)
        if "repo-target" in phases and (run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip()!=TARGET or render_sha()!=observation["servarr"]["target_render_sha256"]): raise Drift("recorded target repository differs")

        if "repo-target" not in phases:
            head=run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip()
            if head==CURRENT:
                if render_sha()!=observation["servarr"]["render_sha256"] or metadata()!=observation["credential"] or current_runtime()!=observation["runtime"]: raise Drift("pre-reset state differs")
                run(["git","-C",str(REPOSITORY),"fetch","--quiet","origin","main"])
                if run(["git","-C",str(REPOSITORY),"rev-parse","origin/main"],capture=True).strip()!=TARGET: raise Drift("origin/main differs from exact target")
                run(["git","-C",str(REPOSITORY),"reset","--hard",TARGET])
            elif head!=TARGET: raise Drift("repository is neither authorized pre-state nor exact target")
            if run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip()!=TARGET or render_sha()!=observation["servarr"]["target_render_sha256"]: raise Drift("target repository state differs")
            try: os.lstat(CREDENTIAL)
            except FileNotFoundError: pass
            else: raise Drift("credential path not absent at repo-target phase")
            if current_runtime()!=observation["runtime"]: raise Drift("runtime changed before init")
            mark_phase("repo-target"); phases.add("repo-target")

        compose=["docker-compose","--project-name","networking","--env-file",str(WORKDIR/".env"),"--env-file","/run/vault-agent/networking.env","-f",str(COMPOSE)]
        pre_by_name={item["name"]:item for item in observation["runtime"]["containers"]}
        if "init-complete" not in phases:
            runtime=current_runtime()
            try: created=metadata()
            except FileNotFoundError:
                if runtime!=observation["runtime"]: raise Drift("pre-init runtime differs")
                run(compose+["up","--no-deps","--force-recreate","--abort-on-container-exit","--exit-code-from","swag-init","swag-init"])
                runtime=current_runtime(); created=metadata()
            validate_runtime(runtime)
            by_name={item["name"]:item for item in runtime["containers"]}
            validate_generated_metadata(created)
            if by_name["swag"]["id"]!=pre_by_name["swag"]["id"] or by_name["swag-init"]["id"]==pre_by_name["swag-init"]["id"]: raise Drift("post-init intermediate state differs")
            init_state={"credential":created,"runtime":runtime}
            if (TRANSITION/"init-state.json").exists():
                if not same_json(TRANSITION/"init-state.json",init_state): raise Drift("init state collision")
            else: write_json(TRANSITION/"init-state.json",init_state); fsync_dir(TRANSITION)
            mark_phase("init-complete"); phases.add("init-complete")
        init_state=read_json(TRANSITION/"init-state.json")
        exact(init_state,{"credential","runtime"},"init state")
        validate_generated_metadata(init_state["credential"]); validate_runtime(init_state["runtime"])
        if runtime_validation_phase(phases)=="init" and current_runtime()!=init_state["runtime"]: raise Drift("recorded init runtime differs")

        if "metadata-complete" not in phases:
            repair_metadata(init_state["credential"])
            repaired=metadata()
            if (repaired["device"],repaired["inode"])!=(init_state["credential"]["device"],init_state["credential"]["inode"]) or (repaired["uid"],repaired["gid"],repaired["mode"])!=(1000,1000,"0600"): raise Drift("metadata-complete state differs")
            write_json(TRANSITION/"metadata-state.json",repaired); fsync_dir(TRANSITION)
            mark_phase("metadata-complete"); phases.add("metadata-complete")
        if metadata()!=read_json(TRANSITION/"metadata-state.json"): raise Drift("recorded credential metadata differs")

        if "swag-complete" not in phases:
            runtime=current_runtime(); by_name={item["name"]:item for item in runtime["containers"]}
            if by_name["swag"]["id"]==pre_by_name["swag"]["id"]:
                if runtime!=init_state["runtime"]: raise Drift("pre-swag intermediate runtime differs")
                run(compose+["up","-d","--no-deps","--force-recreate","swag"]); runtime=current_runtime(); by_name={item["name"]:item for item in runtime["containers"]}
            validate_runtime(runtime)
            if any(by_name[name]["id"]==pre_by_name[name]["id"] for name in ("swag-init","swag")): raise Drift("both container identities must change")
            if (TRANSITION/"final-runtime.json").exists():
                if not same_json(TRANSITION/"final-runtime.json",runtime): raise Drift("final runtime collision")
            else: write_json(TRANSITION/"final-runtime.json",runtime); fsync_dir(TRANSITION)
            mark_phase("swag-complete"); phases.add("swag-complete")
        final_runtime=read_json(TRANSITION/"final-runtime.json")
        if current_runtime()!=final_runtime: raise Drift("exact final runtime differs")

        png=validate_gates()
        if not (TRANSITION/"kindle.png").exists(): write_bytes(TRANSITION/"kindle.png",png)
        else:
            with open(TRANSITION/"kindle.png","rb") as stream:
                if stream.read(8)!=b"\x89PNG\r\n\x1a\n": raise Drift("stored transition PNG invalid")
        result={"credential":metadata(),"kindle_png_sha256":hash_file(TRANSITION/"kindle.png"),"manifest_sha256":expected_sha,"observation_sha256":hashlib.sha256(canonical(observation)).hexdigest(),"runtime_sha256":hashlib.sha256(canonical(final_runtime)).hexdigest(),"status":"passed","target_commit":TARGET,"version":2}
        if (TRANSITION/"result.json").exists():
            if not same_json(TRANSITION/"result.json",result): raise Drift("result collision")
        else: write_json(TRANSITION/"result.json",result)
        fsync_dir(TRANSITION); mark_phase("validated"); fsync_dir(EVIDENCE)
        return result
    finally: os.close(lock_fd)


def validate_completed(expected_sha,authorization):
    if run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip()!=TARGET or render_sha()!=authorization["manifest"]["servarr"]["target_render_sha256"]: raise Drift("completed target repository differs")
    runtime=read_json(TRANSITION/"final-runtime.json")
    validate_runtime(runtime)
    if current_runtime()!=runtime: raise Drift("completed exact runtime differs")
    authorized={item["name"]:item["id"] for item in authorization["manifest"]["runtime"]["containers"]}
    final={item["name"]:item["id"] for item in runtime["containers"]}
    if any(final[name]==authorized[name] for name in ("swag-init","swag")): raise Drift("completed container identities were not replaced")
    credential=read_json(TRANSITION/"metadata-state.json")
    if metadata()!=credential or (credential["uid"],credential["gid"],credential["mode"])!=(1000,1000,"0600"): raise Drift("completed credential metadata differs")
    png_path=TRANSITION/"kindle.png"
    with open(png_path,"rb") as stream:
        if stream.read(8)!=b"\x89PNG\r\n\x1a\n": raise Drift("stored PNG invalid")
    result=read_json(TRANSITION/"result.json")
    expected_observation_sha=hashlib.sha256(canonical(read_json(TRANSITION/"observation.json"))).hexdigest()
    if result != {"credential":credential,"kindle_png_sha256":hash_file(png_path),"manifest_sha256":expected_sha,"observation_sha256":expected_observation_sha,"runtime_sha256":hashlib.sha256(canonical(runtime)).hexdigest(),"status":"passed","target_commit":TARGET,"version":2}: raise Drift("completed evidence hash or fields differ")
    validate_gates()
    return result


def validate_gates():
    identity_format="{{.Id}}|{{.RestartCount}}|{{.State.StartedAt}}|{{.State.Health.Status}}"
    before=run(["docker","inspect","--format",identity_format,"swag"],capture=True).strip()
    status=before.rsplit("|",1)[-1]
    if status!="healthy": raise Drift("SWAG health gate failed")
    run(["docker","exec","swag","nginx","-t"])
    certificate=str(WORKDIR/"config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem")
    run(["openssl","x509","-in",certificate,"-noout","-checkend","604800"])
    san_output=run(["openssl","x509","-in",certificate,"-noout","-ext","subjectAltName"],capture=True)
    sans=sorted(set(re.findall(r"DNS:([^,\s]+)",san_output)))
    if sans != ["*.homelab.pastelariadev.com","*.k8s.pastelariadev.com","ha.pastelariadev.com","k8s.pastelariadev.com"]: raise Drift("certificate SAN set differs")
    assert_no_certbot_hooks()
    run(["docker","exec","swag","certbot","renew","--dry-run","--no-random-sleep-on-renew"])
    run(["curl","--resolve","grafana.homelab.pastelariadev.com:443:192.168.10.210","--fail","--silent","--show-error","--max-time","15","https://grafana.homelab.pastelariadev.com/api/health"])
    adguard=run(["curl","--resolve","adguard.homelab.pastelariadev.com:443:192.168.10.210","--silent","--show-error","--max-time","15","--output","/dev/null","--write-out","%{http_code}","https://adguard.homelab.pastelariadev.com/"],capture=True).strip()
    if adguard!="302": raise Drift("AdGuard route differs")
    png=subprocess.run(["curl","--resolve","kindle.homelab.pastelariadev.com:80:192.168.10.210","--fail","--silent","--show-error","--max-time","30","http://kindle.homelab.pastelariadev.com/dash.png"],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout
    if not png.startswith(b"\x89PNG\r\n\x1a\n"): raise Drift("Kindle route is not PNG")
    after=run(["docker","inspect","--format",identity_format,"swag"],capture=True).strip()
    if after!=before: raise Drift("SWAG restart identity changed during validation")
    return png


def assert_no_certbot_hooks():
    letsencrypt=WORKDIR/"config/swag/etc/letsencrypt"
    configs=list((letsencrypt/"renewal").glob("*.conf"))
    if not configs: raise Drift("Certbot renewal configuration absent")
    hook_re=re.compile(r"^\s*(pre_hook|post_hook|renew_hook|deploy_hook)\s*=\s*(\S.*)?$")
    for config in configs:
        with open(config,encoding="utf-8") as stream:
            for line in stream:
                if line.lstrip().startswith(("#",";")): continue
                match=hook_re.match(line)
                if match and match.group(2): raise Drift("active Certbot renewal hook forbidden")
    for directory in (letsencrypt/"renewal-hooks/pre",letsencrypt/"renewal-hooks/post",letsencrypt/"renewal-hooks/deploy"):
        if directory.is_symlink(): raise Drift("Certbot renewal-hook path differs")
        if directory.exists() and (not directory.is_dir() or any(directory.iterdir())): raise Drift("Certbot renewal-hook directory differs")


def observe(target_render_sha256):
    if not HEX64.fullmatch(target_render_sha256): raise Drift("target render SHA-256 invalid")
    retained_files={"approved_inventory":"approved-inventory.json","archive":"swag-config.tar.zst","archive_checksum":"swag-config.tar.zst.sha256","authorization":"authorization.json","ledger":"ledger.json"}
    retained={name:{"path":str(EVIDENCE/file),"sha256":hash_file(EVIDENCE/file)} for name,file in retained_files.items()}
    snapshot_path=pathlib.Path("/home/.snapshots/stateful-stack-p1-swag")
    snapshot_output=run(["btrfs","subvolume","show",str(snapshot_path)],capture=True)
    snapshot_uuid=next((line.split()[-1] for line in snapshot_output.splitlines() if line.strip().startswith("UUID:")),"")
    if not UUID.fullmatch(snapshot_uuid): raise Drift("snapshot UUID invalid")
    retained["snapshot"]={"path":str(snapshot_path),"uuid":snapshot_uuid}
    entries=sorted(path.name for path in ATTEMPT_02.iterdir())
    phases=sorted(path.name for path in (ATTEMPT_02/"phases").iterdir())
    artifact_files={"authorization":"authorization.json","observation":"observation.json","post_runtime":"post-runtime.json"}
    artifacts={name:{"path":str(ATTEMPT_02/file),"sha256":hash_file(ATTEMPT_02/file)} for name,file in artifact_files.items()}
    run(["discovery-stateful-swag-preflight","resume-verify",str(ATTEMPT_02/"observation.json"),str(ATTEMPT_02/"authorization.json")])
    runtime=json.loads(run(["discovery-stateful-swag-inventory","capture-runtime"],capture=True))
    return {"attempt_01":PREDECESSOR|{"retained":retained},"attempt_02":ATTEMPT_02_BINDING|{"artifacts":artifacts,"phase_markers":phases,"top_level_entries":entries},"credential":metadata(),"runtime":runtime,"servarr":{"commit":run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture=True).strip(),"compose_file":str(COMPOSE),"render_sha256":render_sha(),"target_commit":TARGET,"target_render_sha256":target_render_sha256}}


def read_json(path):
    with open(path,encoding="utf-8") as stream: return json.load(stream)


def main(argv=None):
    parser=argparse.ArgumentParser(); sub=parser.add_subparsers(dest="command",required=True)
    for command in ("plan","verify","execute"):
        item=sub.add_parser(command); item.add_argument("observation")
        if command!="plan": item.add_argument("authorization")
        if command=="execute": item.add_argument("--manifest-sha",required=True)
    observe_parser=sub.add_parser("observe")
    observe_parser.add_argument("--target-render-sha",required=True)
    args=parser.parse_args(argv)
    try:
        if args.command=="observe": result=observe(args.target_render_sha)
        else: observation=read_json(args.observation)
        if args.command=="observe": pass
        elif args.command=="plan": result=envelope(plan(observation))
        elif args.command=="verify": result=verify(observation,read_json(args.authorization))
        else: result=execute(observation,read_json(args.authorization),args.manifest_sha)
    except (Drift,OSError,subprocess.SubprocessError,json.JSONDecodeError) as error:
        print(f"stateful-swag-transition: BLOCKED: {error}",file=sys.stderr); return 1
    print(json.dumps(result,sort_keys=True,separators=(",",":"))); return 0


if __name__=="__main__": raise SystemExit(main())
