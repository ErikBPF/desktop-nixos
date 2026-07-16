#!/usr/bin/env python3
"""Fail-closed P2 AdGuard executor; not installed until declaratively wired."""
import argparse, hashlib, json, os, pathlib, re, stat, subprocess, sys, tempfile

BASE="/var/lib/stateful-stack-migrations/p2-adguard";EXPECTED_LAYOUT={"approved_authorization":BASE+"/authorization.json","approved_inventory":BASE+"/inventory.json","archive":BASE+"/work.tar.zst","archive_checksum":BASE+"/work.tar.zst.sha256","artifact_index":BASE+"/artifact-index.json","config_snapshot":"/home/.snapshots/stateful-stack-p2-adguard","journal":BASE+"/journal.jsonl","ledger":BASE+"/ledger.json","phase_ledger":BASE+"/phase-ledger.json","restore_target":BASE+"/restore-work","revision_forward_authorization":BASE+"/revision-forward-authorization.json","revision_forward_evidence":BASE+"/forward-revision.json","revision_rollback_authorization":BASE+"/revision-rollback-authorization.json","revision_rollback_evidence":BASE+"/rollback-revision.json","rollback_evidence":BASE+"/rollback.json"}
class Drift(ValueError):pass
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
def revision_authorization(channel,revision):
    body={"prefetch":revision["prefetch"],"selected":revision[channel],"selection":channel,"version":1}
    return {"authorization":body,"authorization_sha256":digest(body)}
def file_digest():return hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
def atomic_create(path,payload,mode=0o600):
    path=pathlib.Path(path);path.parent.mkdir(parents=True,exist_ok=True);descriptor,tmp=tempfile.mkstemp(prefix="."+path.name+".",dir=path.parent)
    try:
        os.fchmod(descriptor,mode);os.write(descriptor,payload);os.fsync(descriptor);os.close(descriptor);descriptor=-1;os.link(tmp,path);os.unlink(tmp)
    finally:
        if descriptor>=0:os.close(descriptor)
        pathlib.Path(tmp).unlink(missing_ok=True)
def atomic_replace(path,payload,mode=0o600):
    path=pathlib.Path(path);descriptor,tmp=tempfile.mkstemp(prefix="."+path.name+".",dir=path.parent)
    try:os.fchmod(descriptor,mode);os.write(descriptor,payload);os.fsync(descriptor);os.close(descriptor);descriptor=-1;os.replace(tmp,path)
    finally:
        if descriptor>=0:os.close(descriptor)
        pathlib.Path(tmp).unlink(missing_ok=True)
def append(path,value):
    descriptor=os.open(path,os.O_WRONLY|os.O_APPEND);os.write(descriptor,canonical(value)+b"\n");os.fsync(descriptor);os.close(descriptor)
def metadata(path):
    value=os.lstat(path);xattrs={name:hashlib.sha256(os.getxattr(path,name,follow_symlinks=False)).hexdigest() for name in sorted(os.listxattr(path,follow_symlinks=False))}
    acl=xattrs.get("system.posix_acl_access",hashlib.sha256(f"mode:{stat.S_IMODE(value.st_mode):04o}".encode()).hexdigest())
    return {"acl_sha256":acl,"gid":value.st_gid,"mode":f"{stat.S_IMODE(value.st_mode):04o}","type":stat.S_IFMT(value.st_mode),"uid":value.st_uid,"xattrs":xattrs}
def tree(path):
    root=pathlib.Path(path);result={}
    for item in [root,*sorted(root.rglob("*"))]:
        relative="." if item==root else item.relative_to(root).as_posix();entry=metadata(item)
        if item.is_file() and not item.is_symlink():entry["bytes_sha256"]=hashlib.sha256(item.read_bytes()).hexdigest()
        elif item.is_symlink():entry["target"]=os.readlink(item)
        result[relative]=entry
    return result
def stable_baseline(value):
    api=value["api"];counts={key:api[key] for key in ("enabled_filter_count","filter_count","user_rule_count","query_sample_count","rewrite_count")};counts.update(api["stats"])
    if any(type(item) is not int or item<0 for item in counts.values()):raise Drift("post baseline counts invalid")
    return {"api":{key:api[key] for key in ("enabled_filter_count","filter_count","filtering_enabled","protection_enabled","query_log_enabled","rewrite_count","user_rule_count")},"dns":{name:{"answered":probe["answer_count"]>0,"status":probe["status"]} for name,probe in value["dns"].items()},"exporter":{"families":value["exporter"]["families"],"reachable":value["exporter"]["reachable"],"required_family_count":value["exporter"]["required_family_count"]}}
def validate_recovery_post(manifest,value):
    revision=manifest["revision_contract"]["rollback"]
    if value["servarr"]["commit"]!=revision["commit"] or value["servarr"]["render_sha256"]!=revision["render_sha256"]:raise Drift("recovery revision differs")
    result=validate_post(manifest,value,"rollback");result.update({"revision_commit":revision["commit"],"revision_render_sha256":revision["render_sha256"]});return result
def validate_post(manifest,value,channel="forward"):
    if channel not in ("forward","rollback"):raise Drift("post revision channel differs")
    revision=manifest["revision_contract"][channel]
    if value["servarr"]["commit"]!=revision["commit"] or value["servarr"]["render_sha256"]!=revision["render_sha256"]:raise Drift(f"post {channel} revision differs")
    desired={item["name"]:item for item in manifest["resources"]["containers"]};actual={item["name"]:item for item in value["containers"]}
    if set(actual)!={"adguard","adguard-exporter"}:raise Drift("post container allowlist differs")
    ids={};pre_ids={item["id"] for item in manifest["resources"]["containers"]};images=manifest["resources"]["servarr"]["render_semantics"]["images"]
    for name,wanted in desired.items():
        item=actual[name];ids[name]=item["id"]
        for key in ("compose_labels","compose_project","compose_service","compose_working_dir","mounts","networks"):
            if item[key]!=wanted[key]:raise Drift(f"post {name} {key} differs")
        expected_ref=images[name] if channel=="forward" else wanted["image_ref"];expected_digest=images[name].rsplit("@",1)[1] if channel=="forward" else wanted["image_digest"]
        if item["image_ref"]!=expected_ref or item["image_digest"]!=expected_digest or item["image_id"]!=wanted["image_id"]:raise Drift(f"post {channel} {name} image differs")
        if item["state"]!="running" or item["restart_count"]!=0 or item["health"]!=("healthy" if name=="adguard" else "none") or not re.fullmatch(r"[0-9a-f]{64}",item["id"]):raise Drift(f"post {name} runtime differs")
    volume=value["volume"];wanted_volume=manifest["resources"]["volume"]
    if {**volume,"references":[]}!={**wanted_volume,"references":[]} or volume["references"]!=[ids["adguard"]] or value["config_bind"]!=manifest["resources"]["config_bind"]:raise Drift("post storage differs")
    if len(set(ids.values()))!=2 or set(ids.values())&pre_ids or stable_baseline(value["baseline"])!=stable_baseline(manifest["resources"]["baseline"]):raise Drift("post baseline differs")
    return {"baseline_sha256":digest(stable_baseline(value["baseline"])),"container_ids":ids}
def sanitize_startup_scan(value):
    fields={"containers","fatal_matches","patterns_checked","raw_logs_retained","status","version"}
    if not isinstance(value,dict) or set(value)!=fields or value["containers"]!=["adguard","adguard-exporter"] or not isinstance(value["fatal_matches"],dict) or set(value["fatal_matches"])!={"adguard","adguard-exporter"} or any(type(count) is not int or count<0 for count in value["fatal_matches"].values()) or type(value["patterns_checked"]) is not int or value["patterns_checked"]<=0 or value["raw_logs_retained"] is not False or value["status"]!="passed" or value["version"]!=1:raise Drift("startup fatal scan differs")
    if any(value["fatal_matches"].values()):raise Drift("startup fatal logs detected")
    return {"fatal_matches":value["fatal_matches"],"patterns_checked":value["patterns_checked"],"status":"passed","version":1}
def validate_observation(manifest,value):
    fields={"duration_seconds","end","raw_logs_retained","sample_interval_seconds","samples","start","status","version"}
    if not isinstance(value,dict) or set(value)!=fields or value["duration_seconds"]!=900 or value["sample_interval_seconds"]!=30 or value["samples"]!=31 or value["raw_logs_retained"] is not False or value["status"]!="stable" or value["version"]!=1:raise Drift("stable observation differs")
    if value["start"]!=value["end"]:raise Drift("stable observation points differ")
    start=validate_stable_point(manifest,value["start"]);end=validate_stable_point(manifest,value["end"]);start_ids=start["container_ids"];end_ids=end["container_ids"]
    if start_ids!=end_ids:raise Drift("stable observation identities differ")
    return {"duration_seconds":900,"end_sha256":digest(end),"sample_interval_seconds":30,"samples":31,"start_sha256":digest(start),"status":"stable","version":1}
def validate_stable_point(manifest,value):
    if not isinstance(value,dict) or set(value)!={"baseline","containers"} or value["baseline"]!=stable_baseline(manifest["resources"]["baseline"]):raise Drift("stable point baseline differs")
    containers=value["containers"]
    if not isinstance(containers,dict) or set(containers)!={"adguard","adguard-exporter"}:raise Drift("stable point container allowlist differs")
    desired={item["name"]:item for item in manifest["resources"]["containers"]};images=manifest["resources"]["servarr"]["render_semantics"]["images"];prior={item["id"] for item in manifest["resources"]["containers"]};ids={}
    identity_fields={"compose_labels","compose_project","compose_service","compose_working_dir","image_digest","image_id","image_ref","mounts","networks"}
    for name in ("adguard","adguard-exporter"):
        item=containers[name]
        if not isinstance(item,dict) or set(item)!={"health","id","identity","restart_count","state"} or not isinstance(item["identity"],dict) or set(item["identity"])!=identity_fields:raise Drift(f"stable {name} fields differ")
        expected={key:desired[name][key] for key in ("compose_labels","compose_project","compose_service","compose_working_dir","image_id","mounts","networks")};expected.update({"image_digest":images[name].rsplit("@",1)[1],"image_ref":images[name]});expected_health="healthy" if name=="adguard" else "none"
        if item["identity"]!=expected or item["state"]!="running" or item["health"]!=expected_health or item["restart_count"]!=0 or not re.fullmatch(r"[0-9a-f]{64}",item["id"]) or item["id"] in prior:raise Drift(f"stable {name} differs")
        ids[name]=item["id"]
    if len(set(ids.values()))!=2:raise Drift("stable point identities differ")
    return {"baseline_sha256":digest(value["baseline"]),"container_ids":ids}
def artifact_value(path):
    item=pathlib.Path(path);mode=f"{stat.S_IMODE(item.stat().st_mode):04o}";value=digest(tree(item)) if item.is_dir() else hashlib.sha256(item.read_bytes()).hexdigest();return {"mode":mode,"sha256":value}
def build_artifact_index(layout,journal_prefix,snapshot):
    required=set(layout)-{"artifact_index","journal","revision_rollback_evidence","config_snapshot"};artifacts={name:artifact_value(layout[name]) for name in required};artifacts["config_snapshot"]=snapshot;rollback=pathlib.Path(layout["revision_rollback_evidence"])
    return {"artifacts":artifacts,"journal_prefix_sha256":hashlib.sha256(journal_prefix).hexdigest(),"optional_artifacts":{"revision_rollback_evidence":{"present":rollback.exists(),**({"binding":artifact_value(rollback)} if rollback.exists() else {})}},"version":2}
def validate_revision_evidence(manifest,channel,path):
    try:value=json.loads(pathlib.Path(path).read_text());prefetch=json.loads(pathlib.Path(manifest["revision_contract"]["prefetch"]["path"]).read_text())
    except (OSError,json.JSONDecodeError) as error:raise Drift(f"{channel} revision evidence invalid") from error
    if set(value)!={"evidence","evidence_sha256"}:raise Drift(f"{channel} revision evidence fields differ")
    evidence=value["evidence"];expected_keys={"authorization_sha256","encrypted_blob_changed","head","idempotent","prefetch_sha256","selection","status","tree","version"}
    revision=manifest["revision_contract"][channel];authorization=manifest["revision_authorizations"][channel]
    if set(evidence)!=expected_keys or value["evidence_sha256"]!=digest(evidence) or evidence["authorization_sha256"]!=authorization["authorization_sha256"] or evidence["head"]!=revision["commit"] or evidence["tree"]!=revision["tree"] or evidence["prefetch_sha256"]!=prefetch.get("evidence_sha256") or evidence["selection"]!=channel or evidence["status"]!="activated" or evidence["version"]!=1 or type(evidence["encrypted_blob_changed"]) is not bool or type(evidence["idempotent"]) is not bool:raise Drift(f"{channel} revision evidence differs")
    return {"evidence_sha256":value["evidence_sha256"],"file":artifact_value(path)}
def validate_rollback(manifest,evidence):
    if set(evidence)!={"archive","container","image_sha256","rollback_command_sha256","rollback_not_executed","snapshot"}:raise Drift("rollback evidence fields differ")
    adguard=next(item for item in manifest["resources"]["containers"] if item["name"]=="adguard");expected_image=adguard["image_ref"]+"@"+adguard["image_digest"];rollback=manifest["commands"][1][-2]
    if evidence["archive"]!=manifest["evidence_layout"]["archive"] or evidence["snapshot"]!=manifest["evidence_layout"]["config_snapshot"] or evidence["container"]!=adguard["id"] or evidence["image_sha256"]!=hashlib.sha256(expected_image.encode()).hexdigest() or evidence["rollback_command_sha256"]!=hashlib.sha256(rollback.encode()).hexdigest() or evidence["rollback_not_executed"] is not True:raise Drift("rollback evidence differs")
class ProductionRunner:
    def __init__(self,layout):self.layout=layout
    def capture_inventory(self):
        output=subprocess.run(["/run/current-system/sw/bin/discovery-stateful-adguard-inventory","capture"],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,timeout=30).stdout
        return json.loads(output)
    def snapshot_binding(self,path):
        root=pathlib.Path(path);output=subprocess.run(["btrfs","subvolume","show",root],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True).stdout;matches=re.findall(r"^\s*UUID:\s*([0-9a-f-]+)\s*$",output,re.MULTILINE)
        if len(matches)!=1:raise Drift("snapshot binding invalid")
        return {"path":str(root),"uuid":matches[0]}
    def run(self,phase,argv):
        if phase=="restore-work-non-live":
            target=pathlib.Path(self.layout["restore_target"]);target.mkdir(mode=0o700,parents=False)
        result=subprocess.run(argv,check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=950 if phase=="observe-stable-15-minutes" else 120,cwd="/home/erik/servarr/machines/discovery" if argv[0]=="docker-compose" else None)
        if phase=="verify-bindings":return {"inventory":json.loads(result.stdout)}
        if phase=="snapshot-config-readonly":return {"status":"snapshot-created"}
        if phase in ("scan-startup-fatal-logs","observe-stable-15-minutes"):
            try:return json.loads(result.stdout)
            except (TypeError,json.JSONDecodeError) as error:raise Drift("postcheck output invalid") from error
        if phase=="smoke-test":
            return {"inventory":json.loads(result.stdout)}
        if phase=="verify-recreated-identities":return {"inventory":json.loads(result.stdout)}
        if phase=="record-rollback-evidence":
            rows={};
            for line in result.stdout.decode().splitlines():
                key,separator,value=line.partition("=");
                if not separator or key in rows:raise Drift("rollback helper output invalid")
                rows[key]=value
            if set(rows)!={"archive","container","image","rollback_command","rollback_not_executed","snapshot"}:raise Drift("rollback helper fields differ")
            evidence={"archive":rows["archive"],"container":rows["container"],"image_sha256":hashlib.sha256(rows["image"].encode()).hexdigest(),"rollback_command_sha256":hashlib.sha256(rows["rollback_command"].encode()).hexdigest(),"rollback_not_executed":rows["rollback_not_executed"]=="true","snapshot":rows["snapshot"]};atomic_create(self.layout["rollback_evidence"],canonical(evidence),0o400);return evidence
        return {"stdout_sha256":hashlib.sha256(result.stdout).hexdigest()}
def completed(layout,authorization,runner):
    journal=pathlib.Path(layout["journal"])
    if not journal.exists():return None
    try:rows=[json.loads(line) for line in journal.read_text().splitlines()]
    except (OSError,json.JSONDecodeError):raise Drift("existing journal invalid")
    if rows and rows[-1].get("event")=="completed" and rows[-1].get("manifest_sha256")==authorization:
        index_path=pathlib.Path(layout["artifact_index"]);index=json.loads(index_path.read_text());expected_index_sha=rows[-1].get("artifact_index_sha256")
        if hashlib.sha256(index_path.read_bytes()).hexdigest()!=expected_index_sha or set(index)!={"artifacts","journal_prefix_sha256","optional_artifacts","version"} or index["version"]!=2:raise Drift("artifact index differs")
        lines=journal.read_bytes().splitlines(keepends=True);prefix=b"".join(lines[:-1])
        if hashlib.sha256(prefix).hexdigest()!=index["journal_prefix_sha256"]:raise Drift("journal prefix differs")
        expected_names=set(layout)-{"artifact_index","journal","revision_rollback_evidence"}
        if set(index["artifacts"])!=expected_names:raise Drift("retained artifact differs")
        for name,binding in index["artifacts"].items():
            actual=runner.snapshot_binding(layout[name]) if name=="config_snapshot" else artifact_value(layout[name])
            if actual!=binding:raise Drift("retained artifact differs")
        optional=index["optional_artifacts"]
        if set(optional)!={"revision_rollback_evidence"} or optional["revision_rollback_evidence"]!={"present":False} or pathlib.Path(layout["revision_rollback_evidence"]).exists():raise Drift("optional retained artifact differs")
        return {"idempotent":True,"ledger":json.loads(pathlib.Path(layout["phase_ledger"]).read_text()),"manifest_sha256":authorization,"pending_actions":[],"status":"completed","version":1}
    raise Drift("existing incomplete evidence retained")
def execute(contract,authorization,runner,*,allow_unwired=False,allow_fixture_layout=False):
    if set(contract)!={"manifest","manifest_sha256"} or contract["manifest_sha256"]!=digest(contract["manifest"]) or authorization!=contract["manifest_sha256"]:raise Drift("authorization differs")
    manifest=contract["manifest"];layout=manifest["evidence_layout"]
    if layout!=EXPECTED_LAYOUT and not allow_fixture_layout:raise Drift("evidence layout differs")
    if manifest.get("source_hashes_valid") is not True or manifest["source_hashes"].get("production_executor_sha256")!=file_digest():raise Drift("executor source differs")
    if manifest.get("approval_ready") is not True and not allow_unwired:raise Drift("executor is not declaratively wired")
    revision=manifest.get("revision_contract",{});prefetch=revision.get("prefetch",{});prefetch_path=pathlib.Path(prefetch.get("path",""))
    if not prefetch_path.is_file() or not re.fullmatch(r"[0-9a-f]{64}",prefetch.get("sha256", "")) or hashlib.sha256(prefetch_path.read_bytes()).hexdigest()!=prefetch["sha256"]:raise Drift("revision prefetch evidence differs")
    expected_authorizations={channel:revision_authorization(channel,revision) for channel in ("forward","rollback")}
    if manifest.get("revision_authorizations")!=expected_authorizations:raise Drift("revision authorizations differ")
    prior=completed(layout,authorization,runner)
    if prior:return prior
    fresh=runner.capture_inventory()
    if digest(fresh)!=manifest["inventory_sha256"]:raise Drift("fresh inventory differs")
    for name,path in layout.items():
        if pathlib.Path(path).exists():raise Drift(f"existing evidence path: {name}")
    atomic_create(layout["approved_inventory"],canonical(fresh));atomic_create(layout["approved_authorization"],canonical(contract));atomic_create(layout["revision_forward_authorization"],canonical(manifest["revision_authorizations"]["forward"]),0o444);atomic_create(layout["revision_rollback_authorization"],canonical(manifest["revision_authorizations"]["rollback"]),0o444);atomic_create(layout["phase_ledger"],canonical([]));atomic_create(layout["journal"],b"")
    append(layout["journal"],{"event":"prepared","manifest_sha256":authorization})
    ledger=[];stopped=False
    for phase,argv in zip(manifest["phases"],manifest["commands"],strict=True):
        try:
            stopped=stopped or phase.startswith("stop-")
            evidence=runner.run(phase,argv)
            if phase=="verify-bindings":
                if digest(evidence.get("inventory"))!=manifest["inventory_sha256"]:raise Drift("verify-bindings inventory differs")
                evidence={"inventory_sha256":manifest["inventory_sha256"]}
            if phase=="scan-startup-fatal-logs":evidence=sanitize_startup_scan(evidence)
            if phase=="observe-stable-15-minutes":evidence=validate_observation(manifest,evidence)
            if phase=="activate-forward-revision":evidence=validate_revision_evidence(manifest,"forward",layout["revision_forward_evidence"])
            if phase in {"verify-recreated-identities","smoke-test"}:evidence=validate_post(manifest,evidence["inventory"])
            if phase=="verify-compose-render" and evidence.get("stdout_sha256")!=manifest["resources"]["servarr"]["render_sha256"]:raise Drift("render differs")
            if phase=="record-rollback-evidence":validate_rollback(manifest,evidence)
            row={"evidence":evidence,"phase":phase,"status":"completed"};ledger.append(row);atomic_replace(layout["phase_ledger"],canonical(ledger));append(layout["journal"],row)
        except Exception as error:
            row={"error_class":type(error).__name__,"phase":phase,"status":"failed"};ledger.append(row);append(layout["journal"],row)
            recovery_failed=False;recovery_object={"attempted":False,"status":"not-required"}
            if stopped:
                recovery_object={"attempted":True,"status":"started"};append(layout["journal"],{"event":"recovery-recreate-exact-pair","status":"started"})
                try:
                    recovery_commands=manifest["recovery_commands"]
                    runner.run("recovery-activate-rollback",recovery_commands[0]);activation=validate_revision_evidence(manifest,"rollback",layout["revision_rollback_evidence"]);render=runner.run("recovery-verify-rollback-render",recovery_commands[1])
                    if render.get("stdout_sha256")!=manifest["recovery_render_sha256"]:raise Drift("recovery render differs")
                    recovery=runner.run("recovery-recreate-exact-pair",recovery_commands[2]);recovery_identity=validate_recovery_post(manifest,runner.run("recovery-verify-identities",recovery_commands[3])["inventory"]);recovery_object={"attempted":True,"evidence":{"activation":activation,"render":render,"recreate":recovery,"identity":recovery_identity},"status":"completed"};append(layout["journal"],{"evidence":recovery_object["evidence"],"event":"recovery-recreate-exact-pair","status":"completed"})
                except Exception as recovery_error:
                    recovery_failed=True;rollback_path=pathlib.Path(layout["revision_rollback_evidence"]);recovery_object={"attempted":True,"error_class":type(recovery_error).__name__,"rollback_revision_evidence":artifact_value(rollback_path) if rollback_path.exists() else {"present":False},"status":"failed"};append(layout["journal"],{"error_class":type(recovery_error).__name__,"event":"recovery-recreate-exact-pair","recovery_failed":True,"rollback_revision_evidence":recovery_object["rollback_revision_evidence"],"status":"failed"})
            row["recovery"]=recovery_object;atomic_replace(layout["phase_ledger"],canonical(ledger));return {"failed_phase":phase,"ledger":ledger,"manifest_sha256":authorization,"original_failure_class":type(error).__name__,"pending_actions":manifest["phases"][len(ledger):],"recovery":recovery_object,"recovery_failed":recovery_failed,"status":"recovery-failed" if recovery_failed else "failed","version":1}
    journal_prefix=pathlib.Path(layout["journal"]).read_bytes();index=build_artifact_index(layout,journal_prefix,runner.snapshot_binding(layout["config_snapshot"]));atomic_create(layout["artifact_index"],canonical(index),0o400);append(layout["journal"],{"artifact_index_sha256":hashlib.sha256(pathlib.Path(layout["artifact_index"]).read_bytes()).hexdigest(),"event":"completed","manifest_sha256":authorization});return {"idempotent":False,"ledger":ledger,"manifest_sha256":authorization,"pending_actions":[],"status":"completed","version":1}
def main(argv=None):
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest="command",required=True);item=sub.add_parser("execute");item.add_argument("authorization");item.add_argument("manifest_sha256");args=parser.parse_args(argv)
    try:
        source=os.environ.get("P2_ADGUARD_EXECUTOR_SOURCE","");source_path=pathlib.Path(source)
        if not source or not source_path.is_absolute() or not source_path.is_file() or source_path.resolve()!=pathlib.Path(__file__).resolve():raise Drift("declarative executor source differs")
        contract=json.loads(pathlib.Path(args.authorization).read_text())
        if not re.fullmatch(r"[0-9a-f]{64}",args.manifest_sha256):raise Drift("manifest SHA differs")
        if contract.get("manifest",{}).get("approval_ready") is not True:raise Drift("executor is not declaratively wired")
        result=execute(contract,args.manifest_sha256,ProductionRunner(EXPECTED_LAYOUT))
    except (OSError,ValueError,KeyError,json.JSONDecodeError,subprocess.SubprocessError) as error:print(f"stateful-adguard-transition-exec: BLOCKED: {type(error).__name__}",file=sys.stderr);return 1
    sys.stdout.buffer.write(canonical(result)+b"\n");return 0
if __name__=="__main__":raise SystemExit(main())
