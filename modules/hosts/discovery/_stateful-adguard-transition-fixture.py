#!/usr/bin/env python3
"""Offline-only P2 transition state machine for disposable fixture backends."""
import re
class Drift(ValueError):pass
def exact(value,keys,label):
    if not isinstance(value,dict) or set(value)!=set(keys):raise Drift(f"{label} fields differ")
def normalized_baseline(value):
    api=value["api"]
    return {"api":{key:api[key] for key in ("enabled_filter_count","filter_count","filtering_enabled","protection_enabled","query_log_enabled","rewrite_count","user_rule_count")},"dns":{name:{"answered":probe["answer_count"]>0,"status":probe["status"]} for name,probe in value["dns"].items()},"exporter":{key:value["exporter"][key] for key in ("families","reachable","required_family_count")}}
def validate_startup_logs(value):
    exact(value,{"containers","fatal_matches","patterns_checked","raw_logs_retained","status","version"},"startup log evidence");exact(value["fatal_matches"],{"adguard","adguard-exporter"},"startup fatal matches")
    if value["containers"]!=["adguard","adguard-exporter"] or value["fatal_matches"]!={"adguard":0,"adguard-exporter":0} or type(value["patterns_checked"]) is not int or value["patterns_checked"]<=0 or value["raw_logs_retained"] is not False or value["status"]!="passed" or value["version"]!=1:raise Drift("startup log evidence differs")
    return value
def validate_stable_observation(manifest,value):
    exact(value,{"duration_seconds","end","raw_logs_retained","sample_interval_seconds","samples","start","status","version"},"stable observation")
    if value["duration_seconds"]!=900 or value["sample_interval_seconds"]!=30 or value["samples"]!=31 or value["raw_logs_retained"] is not False or value["status"]!="stable" or value["version"]!=1 or value["start"]!=value["end"]:raise Drift("stable observation bounds differ")
    point=value["start"];exact(point,{"baseline","containers"},"stable observation point");exact(point["containers"],{"adguard","adguard-exporter"},"stable containers")
    if point["baseline"]!=normalized_baseline(manifest["resources"]["baseline"]):raise Drift("stable normalized baseline differs")
    prior={item["id"] for item in manifest["resources"]["containers"]};desired={item["name"]:item for item in manifest["resources"]["containers"]};images=manifest["resources"]["servarr"]["render_semantics"]["images"];ids=[]
    for name in ("adguard","adguard-exporter"):
        item=point["containers"][name];exact(item,{"health","id","identity","restart_count","state"},f"stable {name}");exact(item["identity"],{"compose_labels","compose_project","compose_service","compose_working_dir","image_digest","image_id","image_ref","mounts","networks"},f"stable {name} identity")
        expected_identity={key:desired[name][key] for key in ("compose_labels","compose_project","compose_service","compose_working_dir","image_id","mounts","networks")};expected_identity.update({"image_digest":images[name].rsplit("@",1)[1],"image_ref":images[name]})
        expected_health="healthy" if name=="adguard" else "none"
        if item["identity"]!=expected_identity or item["state"]!="running" or item["health"]!=expected_health or item["restart_count"]!=0 or not re.fullmatch(r"[0-9a-f]{64}",item["id"]) or item["id"] in prior:raise Drift(f"stable {name} differs")
        ids.append(item["id"])
    if len(set(ids))!=2:raise Drift("stable identity differs")
    return value
def execute(contract,authorization,backend,*,completed=None):
    if contract.get("manifest",{}).get("source_hashes_valid") is not True or authorization!=contract.get("manifest_sha256"):raise Drift("fixture contract differs")
    phases=contract["manifest"]["phases"];commands=contract["manifest"]["commands"]
    if completed is not None:
        if completed.get("status")!="completed" or completed.get("manifest_sha256")!=authorization or [row.get("phase") for row in completed.get("ledger",[])]!=phases:raise Drift("completed ledger differs")
        return {**completed,"idempotent":True,"pending_actions":[]}
    ledger=[]
    for phase,argv in zip(phases,commands,strict=True):
        try:
            evidence=backend.run(phase,list(argv))
            if phase=="scan-startup-fatal-logs":evidence=validate_startup_logs(evidence)
            if phase=="observe-stable-15-minutes":evidence=validate_stable_observation(contract["manifest"],evidence)
        except Exception:
            ledger.append({"phase":phase,"status":"failed"});return {"failed_phase":phase,"ledger":ledger,"manifest_sha256":authorization,"pending_actions":phases[len(ledger):],"status":"failed","version":1}
        ledger.append({"evidence":evidence,"phase":phase,"status":"completed"})
    return {"idempotent":False,"ledger":ledger,"manifest_sha256":authorization,"pending_actions":[],"status":"completed","version":1}
