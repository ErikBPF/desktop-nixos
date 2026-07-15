#!/usr/bin/env python3
"""Read-only, value-free Discovery AdGuard inventory collector."""
import argparse, hashlib, json, os, pathlib, re, stat, subprocess, sys, urllib.request

REPOSITORY=pathlib.Path("/home/erik/servarr");WORKDIR=REPOSITORY/"machines/discovery";COMPOSE=WORKDIR/"networking.yml"
ENV_FILE=WORKDIR/".env";VAULT_ENV=pathlib.Path("/run/vault-agent/networking.env");CONFIG=WORKDIR/"config/adguard"
VOLUME="networking_adguard_work";COLLISION="discovery_adguard_work"
RENDER_CONTRACT={"version":1,"cwd":str(WORKDIR),"argv":["docker-compose","--project-name","networking","--project-directory",str(WORKDIR),"--env-file",str(ENV_FILE),"--env-file",str(VAULT_ENV),"-f",str(COMPOSE),"config","--no-interpolate","--no-env-resolution"]}

def run(command,*,binary=False):return subprocess.check_output(command,stderr=subprocess.DEVNULL,text=not binary)
def file_metadata(path,*,with_size=False):
    value=os.lstat(path);result={"device":value.st_dev,"inode":value.st_ino,"uid":value.st_uid,"gid":value.st_gid,"mode":f"{stat.S_IMODE(value.st_mode):04o}","regular":stat.S_ISREG(value.st_mode),"directory":stat.S_ISDIR(value.st_mode),"symlink":stat.S_ISLNK(value.st_mode)}
    if with_size:result["size_bytes"]=int(run(["du","-sb",str(path)]).split()[0])
    return result
def normalize(raw):
    containers=[]
    for item in raw["containers"]:
        labels=item["Config"]["Labels"]
        image_digests=sorted(set(raw["images"][item["Image"]]))
        containers.append({"compose_labels":{"config_files":labels.get("com.docker.compose.project.config_files"),"oneoff":labels.get("com.docker.compose.oneoff"),"version":labels.get("com.docker.compose.version")},"compose_project":labels.get("com.docker.compose.project"),"compose_service":labels.get("com.docker.compose.service"),"compose_working_dir":labels.get("com.docker.compose.project.working_dir"),"health":item["State"].get("Health",{}).get("Status","none"),"id":item["Id"],"image_digest":image_digests[0].split("@")[-1] if len(image_digests)==1 else None,"image_id":item["Image"],"image_ref":item["Config"]["Image"],"mounts":sorted(({"name":mount.get("Name","") if mount["Type"]=="volume" else "","source":mount["Source"],"target":mount["Destination"],"type":mount["Type"]} for mount in item["Mounts"]),key=lambda value:(value["target"],value["source"])),"name":item["Name"].removeprefix("/"),"networks":sorted(item["NetworkSettings"]["Networks"]),"restart_count":item["RestartCount"],"state":item["State"]["Status"]})
    volume=raw["volume"];vm=raw["volume_metadata"]
    return {"baseline":raw["baseline"],"config_bind":{"metadata":raw["config_metadata"],"path":str(CONFIG),"target":"/opt/adguardhome/conf"},"containers":sorted(containers,key=lambda value:value["name"]),"protected_collision":raw["collision"],"servarr":{"commit":raw["servarr"]["commit"],"compose_file":str(COMPOSE),"render_contract":RENDER_CONTRACT,"render_semantics":raw["servarr"]["render_semantics"],"render_sha256":raw["servarr"]["render_sha256"]},"volume":{"driver":volume["Driver"],"labels":volume.get("Labels") or {},"metadata":vm,"mountpoint":volume["Mountpoint"],"name":volume["Name"],"options":volume.get("Options") or {},"ownership":f'{vm["uid"]}:{vm["gid"]}',"references":sorted(raw["volume_references"]),"scope":volume["Scope"],"target":"/opt/adguardhome/work"},"version":1}
def render_semantics(value):
    services=value.get("services",{});selected={}
    for name in ("adguard","adguard-exporter"):
        service=services.get(name,{});mounts=[]
        for mount in service.get("volumes",[]):mounts.append({"source":mount.get("source"),"target":mount.get("target"),"type":mount.get("type")})
        selected[name]=sorted(mounts,key=lambda item:(item["target"],item["source"]))
    volume=value.get("volumes",{}).get("adguard_work",{})
    return {"images":{name:services.get(name,{}).get("image") for name in ("adguard","adguard-exporter")},"mounts":selected,"volumes":{"adguard_work":{"external":volume.get("external") is True,"name":volume.get("name")}}}
def vault_auth():
    return auth_from_env(ENV_FILE)
def auth_from_env(path):
    found=[]
    with open(path,encoding="utf-8") as stream:
        for line in stream:
            key,separator,candidate=line.rstrip("\n").partition("=")
            if separator and key=="ADGUARD_PASSWORD":found.append(candidate)
    if len(found)!=1:raise ValueError("AdGuard API authentication field must occur exactly once")
    value=found[0]
    if len(value)>=2 and value[0]==value[-1] and value[0] in "\"'":value=value[1:-1]
    elif value and (value[:1] in "\"'" or value[-1:] in "\"'"):raise ValueError("AdGuard API authentication field quoting invalid")
    if not value:raise ValueError("AdGuard API authentication field empty")
    return {"username":"erik","password":value}
def api_json(path,auth):
    import base64
    request=urllib.request.Request("http://127.0.0.1:8090"+path,headers={"Authorization":"Basic "+base64.b64encode((auth["username"]+":"+auth["password"]).encode()).decode()})
    with urllib.request.urlopen(request,timeout=10) as response:return json.load(response)
def dns_probe(name,record="A"):
    output=run(["dig","+time=3","+tries=1","+noall","+comments","+answer","@192.168.10.210",name,record])
    status=re.search(r"status: ([A-Z]+)",output);answers=sum(1 for line in output.splitlines() if line and not line.startswith(";"))
    return {"answer_count":answers,"status":status.group(1) if status else "UNKNOWN"}
def baseline():
    auth=vault_auth();status=api_json("/control/status",auth);filters=api_json("/control/filtering/status",auth);query_config=api_json("/control/querylog/config",auth);queries=api_json("/control/querylog?older_than=&limit=1",auth);stats=api_json("/control/stats",auth);rewrites=api_json("/control/rewrite/list",auth)
    metrics=urllib.request.urlopen("http://127.0.0.1:9618/metrics",timeout=10).read().decode("utf-8")
    samples=[line for line in metrics.splitlines() if line and not line.startswith("#")]
    required=("adguard_avg_processing_time","adguard_dns_queries","adguard_num_blocked_filtering")
    return {"api":{"protection_enabled":bool(status.get("protection_enabled")),"filtering_enabled":bool(filters.get("enabled")),"enabled_filter_count":sum(bool(item.get("enabled")) for item in filters.get("filters",[])),"filter_count":len(filters.get("filters",[])),"user_rule_count":len(filters.get("user_rules",[])),"query_log_enabled":bool(query_config.get("enabled")),"query_sample_count":len(queries.get("data",[])),"rewrite_count":len(rewrites),"stats":{"dns_queries":int(stats.get("num_dns_queries",0)),"blocked_filtering":int(stats.get("num_blocked_filtering",0))}},"dns":{"blocked":dns_probe("doubleclick.net"),"external":dns_probe("example.com"),"lan_a":dns_probe("discovery.homelab.pastelariadev.com"),"lan_aaaa":dns_probe("discovery.homelab.pastelariadev.com","AAAA"),"rewrite":dns_probe("grafana.homelab.pastelariadev.com")},"exporter":{"reachable":True,"required_family_count":sum(any(line.startswith(name) for line in samples) for name in required),"sample_count":len(samples)}}
def capture():
    containers=json.loads(run(["docker","inspect","adguard","adguard-exporter"]));images={item["Image"]:json.loads(run(["docker","image","inspect",item["Image"]]))[0].get("RepoDigests",[]) for item in containers}
    volume=json.loads(run(["docker","volume","inspect",VOLUME]))[0];collision_inspect=json.loads(run(["docker","volume","inspect",COLLISION]))[0]
    references=sorted(run(["docker","ps","-aq","--no-trunc","--filter",f"volume={COLLISION}"]).split())
    volume_references=sorted(run(["docker","ps","-aq","--no-trunc","--filter",f"volume={VOLUME}"]).split())
    render=subprocess.run(RENDER_CONTRACT["argv"],cwd=RENDER_CONTRACT["cwd"],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout
    semantics_argv=RENDER_CONTRACT["argv"]+["--format","json"]
    semantics=json.loads(subprocess.run(semantics_argv,cwd=RENDER_CONTRACT["cwd"],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout)
    return normalize({"baseline":baseline(),"collision":{"driver":collision_inspect["Driver"],"exists":True,"labels":collision_inspect.get("Labels") or {},"mountpoint":collision_inspect["Mountpoint"],"name":collision_inspect["Name"],"references":references},"config_metadata":file_metadata(CONFIG),"containers":containers,"images":images,"servarr":{"commit":run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"]).strip(),"render_semantics":render_semantics(semantics),"render_sha256":hashlib.sha256(render).hexdigest()},"volume":volume,"volume_references":volume_references,"volume_metadata":file_metadata(volume["Mountpoint"],with_size=True)})
def main(argv=None):
    parser=argparse.ArgumentParser();parser.add_argument("command",choices=("capture","normalize"));parser.add_argument("input",nargs="?");args=parser.parse_args(argv)
    try:result=capture() if args.command=="capture" else normalize(json.loads(pathlib.Path(args.input).read_text()))
    except (OSError,ValueError,KeyError,json.JSONDecodeError,subprocess.SubprocessError) as error:print(f"stateful-adguard-inventory: BLOCKED: {error}",file=sys.stderr);return 1
    print(json.dumps(result,sort_keys=True,separators=(",",":")));return 0
if __name__=="__main__":raise SystemExit(main())
