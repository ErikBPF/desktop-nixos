#!/usr/bin/env python3
"""Deterministic, value-free P2 AdGuard production command contract."""
import argparse, hashlib, importlib.util, json, os, pathlib, re, sys

HERE=pathlib.Path(__file__).resolve().parent
SOURCE_DEFAULTS={"P2_ADGUARD_INVENTORY_SOURCE":HERE/"_stateful-adguard-inventory.py","P2_ADGUARD_PREFLIGHT_SOURCE":HERE/"_stateful-adguard-preflight.py","P2_ADGUARD_FIXTURE_SOURCE":HERE/"_stateful-adguard-transition-fixture.py","P2_ADGUARD_EXECUTOR_SOURCE":HERE/"_stateful-adguard-transition-exec.py","P2_ADGUARD_REVISION_SOURCE":HERE/"_stateful-adguard-transition-revision.py","P2_ADGUARD_EXACT_REVISION_SOURCE":HERE.parents[1]/"server/_servarr-exact-revision.py","P2_ADGUARD_POSTCHECK_SOURCE":HERE/"_stateful-adguard-postcheck.py"}
def resolved_source(name):
    candidate=os.environ.get(name,"");path=pathlib.Path(candidate) if candidate and pathlib.Path(candidate).is_absolute() and pathlib.Path(candidate).is_file() else SOURCE_DEFAULTS[name]
    return path.resolve()
INVENTORY_SOURCE=resolved_source("P2_ADGUARD_INVENTORY_SOURCE");PREFLIGHT_SOURCE=resolved_source("P2_ADGUARD_PREFLIGHT_SOURCE");FIXTURE_SOURCE=resolved_source("P2_ADGUARD_FIXTURE_SOURCE");EXECUTOR_SOURCE=resolved_source("P2_ADGUARD_EXECUTOR_SOURCE");REVISION_SOURCE=resolved_source("P2_ADGUARD_REVISION_SOURCE");EXACT_REVISION_SOURCE=resolved_source("P2_ADGUARD_EXACT_REVISION_SOURCE");POSTCHECK_SOURCE=resolved_source("P2_ADGUARD_POSTCHECK_SOURCE")
_spec=importlib.util.spec_from_file_location("adguard_transition_revision",REVISION_SOURCE);REVISION=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(REVISION)
_exact_spec=importlib.util.spec_from_file_location("servarr_exact_revision_contract",EXACT_REVISION_SOURCE);EXACT_REVISION=importlib.util.module_from_spec(_exact_spec);_exact_spec.loader.exec_module(EXACT_REVISION)
HEX64=re.compile(r"^[0-9a-f]{64}$");WORKDIR="/home/erik/servarr/machines/discovery";COMPOSE=WORKDIR+"/networking.yml"
POSTCHECK_BIN="discovery-stateful-adguard-postcheck"
FATAL_LOG_PATTERNS=("fatal","panic","segmentation fault","address already in use","permission denied","read-only file system")
BASE="/var/lib/stateful-stack-migrations/p2-adguard"
LAYOUT={"approved_authorization":BASE+"/authorization.json","approved_inventory":BASE+"/inventory.json","archive":BASE+"/work.tar.zst","archive_checksum":BASE+"/work.tar.zst.sha256","artifact_index":BASE+"/artifact-index.json","config_snapshot":"/home/.snapshots/stateful-stack-p2-adguard","journal":BASE+"/journal.jsonl","ledger":BASE+"/ledger.json","phase_ledger":BASE+"/phase-ledger.json","restore_target":BASE+"/restore-work","revision_forward_authorization":BASE+"/revision-forward-authorization.json","revision_forward_evidence":BASE+"/forward-revision.json","revision_rollback_authorization":BASE+"/revision-rollback-authorization.json","revision_rollback_evidence":BASE+"/rollback-revision.json","rollback_evidence":BASE+"/rollback.json"}
PHASES=["verify-bindings","write-ledger","stop-adguard-exporter","stop-adguard","snapshot-config-readonly","archive-work-volume","checksum-list-read-archive","restore-work-non-live","compare-non-live-restore","activate-forward-revision","verify-compose-render","recreate-exact-pair","verify-recreated-identities","scan-startup-fatal-logs","observe-stable-15-minutes","smoke-test","record-rollback-evidence"]
RESULT_FIELDS={"actual_elapsed_ms","core_evidence","core_partial_results_sha256","core_results_sha256","core_row_count","diagnostic_evidence","diagnostic_results_sha256","diagnostic_row_count","diagnostic_status","failover_bound_ms","manifest_sha256","original_failure_rc","outage_results_sha256","partial_diagnostic_results_sha256","partial_outage_results_sha256","postrestore_evidence","postrestore_results_sha256","postrestore_row_count","postrestore_status","recovery_failed","shared_nonce_sha256","status","version"}
MANIFEST_FIELDS={"actions","bindings","diagnostic_workers","evidence_phases","inventory_sha256","mode","network_contract_sha256","probe_contracts","probe_evidence","required_workers","resources","shared_nonce","version"}
class Drift(ValueError):pass
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
def inventory_digest(value):
    normalized=json.loads(json.dumps(value));stats=normalized["baseline"]["api"]["stats"]
    if set(stats)!={"blocked_filtering","dns_queries"} or any(type(item) is not int or item<0 for item in stats.values()):raise Drift("inventory counters invalid")
    stats.update(blocked_filtering=0,dns_queries=0);return digest(normalized)
def file_digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def envelope(value):return {"manifest":value,"manifest_sha256":digest(value)}
def exact(value,keys,label):
    if not isinstance(value,dict) or set(value)!=set(keys):raise Drift(f"{label} fields differ")
def validate_p3(bundle):
    exact(bundle,{"manifest_envelope","observation","result"},"P3 bundle");manifest_envelope=bundle["manifest_envelope"];result=bundle["result"];observation=bundle["observation"]
    exact(manifest_envelope,{"manifest","manifest_sha256"},"P3 manifest envelope");manifest=manifest_envelope["manifest"];exact(manifest,MANIFEST_FIELDS,"P3 manifest")
    if manifest_envelope["manifest_sha256"]!=digest(manifest) or manifest["version"]!=4 or manifest["mode"]!="approved-outage-drill" or manifest["resources"]!=["adguard-exporter","adguard"] or manifest["inventory_sha256"]!=digest(observation):raise Drift("P3 manifest binding differs")
    exact(result,RESULT_FIELDS,"P3 result")
    hashes=("manifest_sha256","core_results_sha256","core_partial_results_sha256","outage_results_sha256","partial_outage_results_sha256","postrestore_results_sha256","shared_nonce_sha256")
    if result["version"]!=4 or result["status"]!="passed" or result["original_failure_rc"]!=0 or result["recovery_failed"] is not False or result["manifest_sha256"]!=manifest_envelope["manifest_sha256"] or any(not HEX64.fullmatch(result[key] or "") for key in hashes):raise Drift("P3 result differs")
    if result["core_evidence"]!={"rows":24,"status":"complete"} or result["core_row_count"]!=24 or result["core_results_sha256"]!=result["core_partial_results_sha256"] or result["core_results_sha256"]!=result["outage_results_sha256"] or result["postrestore_evidence"].get("status")!="complete" or result["postrestore_evidence"].get("rows")!=result["postrestore_row_count"] or result["postrestore_row_count"]<=0 or result["postrestore_status"]!="complete":raise Drift("P3 completion evidence differs")
def source_hashes():return {"exact_revision_helper_sha256":file_digest(EXACT_REVISION_SOURCE),"fixture_executor_sha256":file_digest(FIXTURE_SOURCE),"inventory_helper_sha256":file_digest(INVENTORY_SOURCE),"planner_sha256":file_digest(pathlib.Path(__file__)),"postcheck_helper_sha256":file_digest(POSTCHECK_SOURCE),"preflight_sha256":file_digest(PREFLIGHT_SOURCE),"production_executor_sha256":file_digest(EXECUTOR_SOURCE),"revision_helper_sha256":file_digest(REVISION_SOURCE)}
def commands(resources,layout,revisions):
    by_name={item["name"]:item for item in resources["containers"]}
    render=list(resources["servarr"]["render_contract"]["argv"]);compose=render[:render.index("config")]
    forward_output=layout["revision_forward_evidence"];rollback_output=layout["revision_rollback_evidence"]
    binary=os.environ.get("P2_ADGUARD_EXACT_REVISION_BIN","servarr-exact-revision")
    recovery=[REVISION.activation_argv("rollback",revisions,layout["revision_rollback_authorization"],rollback_output,binary),render,compose+["up","-d","--no-deps","--force-recreate","adguard","adguard-exporter"],["discovery-stateful-adguard-inventory","capture"]]
    rollback=json.dumps(recovery,sort_keys=True,separators=(",",":"))
    return [
      ["discovery-stateful-adguard-inventory","capture"],["discovery-stateful-stack-ops","ledger-create",layout["ledger"],"/home/erik/servarr",by_name["adguard"]["id"],"/opt/adguardhome/work","/home",layout["config_snapshot"],layout["archive"],layout["restore_target"],rollback,"120s"],
      ["docker","stop",by_name["adguard-exporter"]["id"]],["docker","stop",by_name["adguard"]["id"]],
      ["discovery-stateful-stack-ops","snapshot",layout["ledger"]],
      ["discovery-stateful-stack-ops","archive",layout["ledger"]],
      ["discovery-stateful-stack-ops","read-verify",layout["ledger"]],["discovery-stateful-stack-ops","restore",layout["ledger"],layout["restore_target"]],
      ["discovery-stateful-stack-ops","compare",layout["ledger"],layout["restore_target"]],REVISION.activation_argv("forward",revisions,layout["revision_forward_authorization"],forward_output,binary),render,
      compose+["up","-d","--no-deps","--force-recreate","adguard","adguard-exporter"],["discovery-stateful-adguard-inventory","capture"],
      [os.environ.get("P2_ADGUARD_POSTCHECK_BIN",POSTCHECK_BIN),"startup-fatal-log-scan","--containers","adguard,adguard-exporter","--since","container-start","--output","counts-only","--fatal-patterns","|".join(FATAL_LOG_PATTERNS)],
      [os.environ.get("P2_ADGUARD_POSTCHECK_BIN",POSTCHECK_BIN),"stable-observation","--containers","adguard,adguard-exporter","--duration-seconds","900","--sample-interval-seconds","30","--baseline","full-normalized-start-end","--identity","exact-new-and-stable","--health","exact","--restarts","zero","--raw-logs","discard"],
      ["discovery-stateful-adguard-inventory","capture"],["discovery-stateful-stack-ops","rollback-evidence",layout["ledger"]],
    ],recovery
def plan(inventory,p3_bundle,layout,revisions,*,preflight):
    if layout!=LAYOUT:raise Drift("evidence layout differs")
    try:preflight_manifest=preflight.plan(inventory)
    except ValueError as error:raise Drift("inventory preflight differs") from error
    validate_p3(p3_bundle)
    try:REVISION.validate(revisions,os.environ.get("P2_ADGUARD_REVISION_PREFETCH_PATH",REVISION.PREFETCH_PATH))
    except REVISION.Drift as error:raise Drift(str(error)) from error
    if revisions["forward"]["render_sha256"]!=inventory["servarr"]["render_sha256"]:raise Drift("forward render differs")
    resources={"baseline":inventory["baseline"],"config_bind":inventory["config_bind"],"containers":inventory["containers"],"servarr":inventory["servarr"],"volume":inventory["volume"]}
    hashes=source_hashes()
    hashes_valid=all(HEX64.fullmatch(value) for value in hashes.values())
    main,recovery=commands(resources,layout,revisions);wiring=os.environ.get("P2_ADGUARD_DECLARATIVE_WIRING_SHA256","");binary=os.environ.get("P2_ADGUARD_EXACT_REVISION_BIN","");postcheck_wiring=os.environ.get("P2_ADGUARD_POSTCHECK_WIRING_SHA256","");postcheck_binary=os.environ.get("P2_ADGUARD_POSTCHECK_BIN","");revision_wiring_valid=wiring==hashes["exact_revision_helper_sha256"] and binary.startswith("/nix/store/") and pathlib.Path(binary).is_absolute();postcheck_wiring_valid=postcheck_wiring==hashes["postcheck_helper_sha256"] and postcheck_binary.startswith("/nix/store/") and pathlib.Path(postcheck_binary).is_absolute();wiring_valid=revision_wiring_valid and postcheck_wiring_valid;blockers=[] if wiring_valid else ([] if revision_wiring_valid else ["declarative_executor_wiring_absent","revision_activation_helper_unwired"])+([] if postcheck_wiring_valid else ["postcheck_helper_unwired"])
    authorizations={channel:REVISION.authorization(channel,revisions) for channel in ("forward","rollback")}
    return {"approval_ready":wiring_valid,"blockers":blockers,"commands":main,"declarative_wiring_sha256":wiring if wiring_valid else None,"evidence_layout":layout,"inventory_sha256":inventory_digest(inventory),"mode":"production-command-contract" if wiring_valid else "production-command-contract-draft","p3_manifest_envelope_sha256":digest(p3_bundle["manifest_envelope"]),"p3_observation_sha256":digest(p3_bundle["observation"]),"p3_result_sha256":digest(p3_bundle["result"]),"phase":"p2-adguard-in-place-adoption","phases":PHASES,"preflight_manifest_sha256":digest(preflight_manifest),"recovery_commands":recovery,"recovery_render_sha256":revisions["rollback"]["render_sha256"],"resources":resources,"revision_authorizations":authorizations,"revision_contract":revisions,"source_hashes":hashes,"source_hashes_valid":hashes_valid,"version":6}
def read(path):return json.loads(pathlib.Path(path).read_text())
def revisions_from_prefetch(path):
    resolved=pathlib.Path(path).resolve();expected=os.environ.get("P2_ADGUARD_REVISION_PREFETCH_PATH",REVISION.PREFETCH_PATH)
    if not pathlib.Path(expected).is_absolute() or str(resolved)!=expected:raise Drift("revision prefetch path differs")
    raw=resolved.read_bytes();value=json.loads(raw);EXACT_REVISION.validate_prefetch(value)
    contract=value["contract"]
    return {"forward":contract["forward"],"prefetch":{"path":str(resolved),"sha256":hashlib.sha256(raw).hexdigest()},"rollback":contract["rollback"]}
def cli_plan(paths):
    inventory=read(paths[0]);p3={"manifest_envelope":read(paths[1]),"observation":read(paths[2]),"result":read(paths[3])};revisions=revisions_from_prefetch(paths[4])
    return envelope(plan(inventory,p3,LAYOUT,revisions,preflight=load_preflight()))
def load_preflight():
    spec=importlib.util.spec_from_file_location("stateful_adguard_preflight_cli",PREFLIGHT_SOURCE);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def validate_cli_sources():
    for name in SOURCE_DEFAULTS:
        candidate=os.environ.get(name,"");path=pathlib.Path(candidate)
        if not candidate or not path.is_absolute() or not path.is_file() or path.resolve()!=resolved_source(name):raise Drift("declarative source path differs")
    prefetch=os.environ.get("P2_ADGUARD_REVISION_PREFETCH_PATH","")
    if not prefetch or not pathlib.Path(prefetch).is_absolute() or not pathlib.Path(prefetch).is_file():raise Drift("declarative prefetch path differs")
    binary=os.environ.get("P2_ADGUARD_EXACT_REVISION_BIN","")
    if not binary.startswith("/nix/store/") or not pathlib.Path(binary).is_absolute():raise Drift("exact revision binary path differs")
    postcheck=os.environ.get("P2_ADGUARD_POSTCHECK_BIN","")
    if not postcheck.startswith("/nix/store/") or not pathlib.Path(postcheck).is_absolute():raise Drift("postcheck binary path differs")
def main(argv=None):
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest="command",required=True)
    for command in ("plan","verify"):
        item=sub.add_parser(command)
        for name in ("inventory","p3_manifest","p3_observation","p3_result","revision_prefetch"):item.add_argument(name)
        if command=="verify":item.add_argument("authorization")
    args=parser.parse_args(argv);paths=[args.inventory,args.p3_manifest,args.p3_observation,args.p3_result,args.revision_prefetch]
    try:
        validate_cli_sources()
        expected=cli_plan(paths)
        if args.command=="plan":result=expected
        else:
            if read(args.authorization)!=expected:raise Drift("authorization binding differs")
            result={"manifest_sha256":expected["manifest_sha256"],"status":"binding-valid","version":1}
    except (OSError,ValueError,KeyError,json.JSONDecodeError,EXACT_REVISION.ContractError) as error:print(f"stateful-adguard-transition: BLOCKED: {type(error).__name__}",file=sys.stderr);return 1
    sys.stdout.buffer.write(canonical(result)+b"\n");return 0
if __name__=="__main__":raise SystemExit(main())
