#!/usr/bin/env python3
"""Deterministic, value-free P2 AdGuard preflight planner."""
import argparse, hashlib, json, os, pathlib, re, sys
HEX64=re.compile(r"^[0-9a-f]{64}$");HEX40=re.compile(r"^[0-9a-f]{40}$")
ACTIONS=["bind-existing-physical-volume","bind-dependent-container-identities","record-baseline-without-mutation"]
WORKDIR="/home/erik/servarr/machines/discovery";COMPOSE=WORKDIR+"/networking.yml"
RENDER_CONTRACT={"version":1,"cwd":WORKDIR,"argv":["docker-compose","--project-name","networking","--project-directory",WORKDIR,"--env-file",WORKDIR+"/.env","--env-file","/run/vault-agent/networking.env","-f",COMPOSE,"config","--no-interpolate","--no-env-resolution"]}
TARGET_COMMIT=os.environ.get("P2_ADGUARD_TARGET_COMMIT","")
TARGET_IMAGE_REFS={"adguard":os.environ.get("P2_ADGUARD_IMAGE_ADGUARD",""),"adguard-exporter":os.environ.get("P2_ADGUARD_IMAGE_EXPORTER","")}
EXPECTED_EXPORTER_FAMILIES={"adguard_avg_processing_time","adguard_dns_queries","adguard_num_blocked_filtering"}
class Drift(ValueError):pass
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def envelope(value):return {"manifest":value,"manifest_sha256":hashlib.sha256(canonical(value)).hexdigest()}
def exact(value,keys,label):
    if not isinstance(value,dict) or set(value)!=set(keys):raise Drift(f"{label} fields differ")
def nonnegative(value):return type(value) is int and value>=0
def validate_metadata(value,label,*,size=False):
    keys={"device","inode","uid","gid","mode","regular","directory","symlink"}|({"size_bytes"} if size else set());exact(value,keys,label)
    if not all(nonnegative(value[key]) for key in ("device","inode","uid","gid")) or not re.fullmatch(r"0[0-7]{3}",value["mode"]) or value["directory"] is not True or value["regular"] is not False or value["symlink"] is not False or (size and not nonnegative(value["size_bytes"])):raise Drift(f"{label} invalid")
def plan(inventory):
    exact(inventory,{"baseline","config_bind","containers","protected_collision","servarr","version","volume"},"inventory")
    if inventory["version"]!=1:raise Drift("inventory version differs")
    containers=inventory["containers"]
    if not isinstance(containers,list) or len(containers)!=2 or {x.get("name") for x in containers}!={"adguard","adguard-exporter"}:raise Drift("container allowlist differs")
    expected_images={"adguard":"adguard/adguardhome:v0.108.0-b.83","adguard-exporter":"ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1"}
    for item in containers:
        exact(item,{"compose_labels","compose_project","compose_service","compose_working_dir","health","id","image_digest","image_id","image_ref","mounts","name","networks","restart_count","state"},item.get("name","container"));name=item["name"]
        exact(item["compose_labels"],{"config_files","oneoff","version"},"Compose labels")
        target_ref=TARGET_IMAGE_REFS[name]
        if not target_ref or item["compose_project"]!="networking" or item["compose_service"]!=name or item["compose_working_dir"]!=WORKDIR or item["compose_labels"]["config_files"]!=COMPOSE or item["compose_labels"]["oneoff"]!="False" or not re.fullmatch(r"\d+\.\d+\.\d+",item["compose_labels"]["version"] or "") or item["networks"]!=["homelab-net"] or item["restart_count"]!=0 or item["state"]!="running" or item["health"]!=("healthy" if name=="adguard" else "none") or item["image_ref"]!=expected_images[name] or not target_ref.startswith(expected_images[name]+"@sha256:") or item["image_digest"]!=target_ref.rsplit("@",1)[1] or not HEX64.fullmatch(item["id"]) or not re.fullmatch(r"sha256:[0-9a-f]{64}",item["image_id"]):raise Drift("container identity differs")
    volume=inventory["volume"];exact(volume,{"driver","labels","metadata","mountpoint","name","options","ownership","references","scope","target"},"volume");validate_metadata(volume["metadata"],"volume metadata",size=True)
    adguard_id=next(item["id"] for item in containers if item["name"]=="adguard")
    if volume["name"]!="networking_adguard_work" or volume["driver"]!="local" or volume["scope"]!="local" or volume["options"]!={} or volume["references"]!=[adguard_id] or volume["target"]!="/opt/adguardhome/work" or volume["ownership"]!="65534:65534" or (volume["metadata"]["uid"],volume["metadata"]["gid"])!=(65534,65534) or volume["metadata"]["size_bytes"]<=0 or volume["labels"].get("com.docker.compose.project")!="networking":raise Drift("physical volume differs")
    config=inventory["config_bind"];exact(config,{"metadata","path","target"},"config bind");validate_metadata(config["metadata"],"config metadata")
    if config["path"]!="/home/erik/servarr/machines/discovery/config/adguard" or config["target"]!="/opt/adguardhome/conf" or (config["metadata"]["uid"],config["metadata"]["gid"])!=(1000,100):raise Drift("config bind differs")
    by_name={item["name"]:item for item in containers}
    if by_name["adguard"]["mounts"]!=sorted([{"name":"networking_adguard_work","source":volume["mountpoint"],"target":"/opt/adguardhome/work","type":"volume"},{"name":"","source":config["path"],"target":"/opt/adguardhome/conf","type":"bind"}],key=lambda value:(value["target"],value["source"])) or by_name["adguard-exporter"]["mounts"]!=[]:raise Drift("container mounts differ")
    collision=inventory["protected_collision"];exact(collision,{"driver","exists","labels","mountpoint","name","references"},"collision")
    if collision["exists"] is not True or collision["name"]!="discovery_adguard_work" or collision["driver"]!="local" or collision["references"]!=[]:raise Drift("protected collision differs")
    servarr=inventory["servarr"]
    exact(servarr,{"commit","compose_file","render_contract","render_semantics","render_sha256"},"Servarr")
    expected_semantics={"images":TARGET_IMAGE_REFS,"mounts":{"adguard":sorted([{"source":"adguard_work","target":"/opt/adguardhome/work","type":"volume"},{"source":WORKDIR+"/config/adguard","target":"/opt/adguardhome/conf","type":"bind"}],key=lambda item:(item["target"],item["source"])),"adguard-exporter":[]},"volumes":{"adguard_work":{"external":True,"name":"networking_adguard_work"}}}
    if TARGET_COMMIT=="" or servarr["commit"]!=TARGET_COMMIT or not HEX40.fullmatch(servarr["commit"]) or not HEX64.fullmatch(servarr["render_sha256"]) or servarr["compose_file"]!=COMPOSE or servarr["render_contract"]!=RENDER_CONTRACT or servarr["render_semantics"]!=expected_semantics:raise Drift("Servarr binding differs")
    baseline=inventory["baseline"];exact(baseline,{"api","dns","exporter"},"baseline");api=baseline["api"]
    exact(api,{"protection_enabled","filtering_enabled","enabled_filter_count","filter_count","user_rule_count","query_log_enabled","query_sample_count","rewrite_count","stats"},"API baseline");exact(api["stats"],{"blocked_filtering","dns_queries"},"stats")
    if any(api[key] is not True for key in ("protection_enabled","filtering_enabled","query_log_enabled")) or any(not nonnegative(api[key]) for key in ("enabled_filter_count","filter_count","user_rule_count","query_sample_count","rewrite_count")) or api["enabled_filter_count"]>api["filter_count"] or any(not nonnegative(api["stats"][key]) for key in api["stats"]):raise Drift("API counts invalid")
    exact(baseline["dns"],{"blocked","external","lan_a","lan_aaaa","rewrite"},"DNS probes")
    for probe in baseline["dns"].values():
        exact(probe,{"answer_count","status"},"DNS probe")
        if not nonnegative(probe["answer_count"]) or not re.fullmatch(r"[A-Z]+",probe["status"]):raise Drift("DNS probe invalid")
    if any(baseline["dns"][name]["status"]!="NOERROR" or baseline["dns"][name]["answer_count"]<1 for name in ("blocked","external","lan_a","rewrite")) or baseline["dns"]["lan_aaaa"]["status"]!="NOERROR":raise Drift("DNS baseline differs")
    exact(baseline["exporter"],{"families","reachable","sample_count"},"exporter");exact(baseline["exporter"]["families"],EXPECTED_EXPORTER_FAMILIES,"exporter families")
    if baseline["exporter"]["reachable"] is not True or any(value is not True for value in baseline["exporter"]["families"].values()) or not nonnegative(baseline["exporter"]["sample_count"]):raise Drift("exporter baseline invalid")
    stable_baseline={"api":{"filtering_enabled":api["filtering_enabled"],"protection_enabled":api["protection_enabled"],"query_log_enabled":api["query_log_enabled"]},"dns":{name:{"answered":probe["answer_count"]>0,"status":probe["status"]} for name,probe in baseline["dns"].items()},"exporter":{"families":baseline["exporter"]["families"],"reachable":baseline["exporter"]["reachable"]}}
    resources={"config_bind":config,"containers":containers,"volume":volume}
    stable_identity={"baseline":stable_baseline,"protected_collision":collision,"resources":resources,"servarr":servarr}
    return {"actions":ACTIONS,"approval_ready":False,"baseline":stable_baseline,"blockers":["backup_restore_evidence","secondary_dns_or_waiver"],"mode":"preflight-only","phase":"p2-adguard-in-place-adoption","protected_collision":collision,"resources":resources,"servarr":servarr,"stable_inventory_sha256":hashlib.sha256(canonical(stable_identity)).hexdigest(),"version":2}
def verify(inventory,authorization):
    expected=envelope(plan(inventory))
    if authorization!=expected:raise Drift("inventory or manifest binding differs")
    return {"manifest_sha256":expected["manifest_sha256"],"stable_inventory_sha256":expected["manifest"]["stable_inventory_sha256"],"status":"binding-valid"}
def read(path):return json.loads(pathlib.Path(path).read_text())
def main(argv=None):
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest="command",required=True);p=sub.add_parser("plan");p.add_argument("inventory");v=sub.add_parser("verify");v.add_argument("inventory");v.add_argument("authorization");args=parser.parse_args(argv)
    try:result=envelope(plan(read(args.inventory))) if args.command=="plan" else verify(read(args.inventory),read(args.authorization))
    except (OSError,ValueError,json.JSONDecodeError) as error:print(f"stateful-adguard-preflight: BLOCKED: {error}",file=sys.stderr);return 1
    print(json.dumps(result,sort_keys=True,separators=(",",":")));return 0
if __name__=="__main__":raise SystemExit(main())
