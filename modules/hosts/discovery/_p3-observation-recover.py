#!/usr/bin/env python3
"""Offline, value-free recovery of a P3 observation's probe evidence."""
import hashlib,ipaddress,json,os,pathlib,re,stat,sys,tempfile

HASH=re.compile(r"^[0-9a-f]{64}$")
EXPECTED_MANIFEST_SHA256="d5cf3b5979d88ece2582df3010d28e5f89fc7e440dc31c4838f6b1f28ee3cc40"
EXPECTED_RECOVERED_INVENTORY_SHA256="6977c47a3779bdd1086473065bb106b6b9a4ff54bf8c540a9924632446cf6601"
EXPECTED_CURRENT_OBSERVATION_SHA256="be6a935c0e228fdffb1ac90185df767eb21ab23c0401b4b36b2c689ce14def59"
EXPECTED_DIAGNOSTIC_RESULTS_SHA256="aebce43d85fc62812445e079e471066014aff901cdd4dbebb00c1bcfd83c5629"
MANIFEST_FIELDS={"actions","bindings","diagnostic_workers","evidence_phases","inventory_sha256","mode","network_contract_sha256","probe_contracts","probe_evidence","required_workers","resources","shared_nonce","version"}
RESULT_FIELDS={"actual_elapsed_ms","core_evidence","core_partial_results_sha256","core_results_sha256","core_row_count","diagnostic_evidence","diagnostic_results_sha256","diagnostic_row_count","diagnostic_status","failover_bound_ms","manifest_sha256","original_failure_rc","outage_results_sha256","partial_diagnostic_results_sha256","partial_outage_results_sha256","postrestore_evidence","postrestore_results_sha256","postrestore_row_count","postrestore_status","recovery_failed","shared_nonce_sha256","status","version"}
PROBE_FIELDS={"classifications_sha256","nonce_sha256","qnames_sha256","results_sha256"}
ROW=re.compile(r"^(0[1-4]):(0[1-6]):(.+):(udp|tcp):(A|AAAA):(fleet-a|fleet-aaaa|external|nxdomain|filtered):observed_rc=0:observed_status=(NOERROR|NXDOMAIN):answer_count_class=(zero|positive):answer_classification=(fleet-a|nodata|external-positive|nxdomain|filtered-nxdomain|filtered-null):qname_sha256=([0-9a-f]{64})$")
ROW_CONTRACTS=(("A","fleet-a"),("AAAA","fleet-aaaa"),("A","external"),("AAAA","external"),("A","nxdomain"),("A","filtered"))
PREFIX=[("stop-exporter","started"),("stop-exporter","passed"),("stop-adguard","started"),("stop-adguard","passed"),("stopped-gate","started"),("stopped-gate","passed"),("failover-probe","started"),("gateway-diagnostic","started"),("failover-probe","passed"),("gateway-diagnostic","captured"),("outage-proof","passed")]

class Blocked(Exception):pass
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
def load(path):
    try:return json.loads(pathlib.Path(path).read_bytes())
    except (OSError,UnicodeError,json.JSONDecodeError) as exc:raise Blocked("invalid-input") from exc
def parse(raw):
    try:return json.loads(raw)
    except (UnicodeError,json.JSONDecodeError) as exc:raise Blocked("invalid-input") from exc
def exact(value,fields,label):
    if not isinstance(value,dict) or set(value)!=fields:raise Blocked(label+"-schema")
def valid_hash(value):return isinstance(value,str) and HASH.fullmatch(value) is not None
def parse_row(row):
    match=ROW.fullmatch(row)
    if match is None:return None
    ordinal,item,resolver,transport,qtype,contract,status,count,classification,qname=match.groups()
    if (qtype,contract)!=ROW_CONTRACTS[int(item)-1]:return None
    semantics={"fleet-a":{("NOERROR","positive","fleet-a")},"fleet-aaaa":{("NOERROR","zero","nodata")},"external":{("NOERROR","positive","external-positive")},"nxdomain":{("NXDOMAIN","zero","nxdomain")},"filtered":{("NXDOMAIN","zero","filtered-nxdomain"),("NOERROR","positive","filtered-null")}}
    if (status,count,classification) not in semantics[contract]:return None
    return {"classification":classification,"contract":contract,"count":count,"item":item,"ordinal":ordinal,"qname":qname,"resolver":resolver,"status":status,"transport":transport,"type":qtype}
def write_once(path,data):
    target=pathlib.Path(path);target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists() or target.is_symlink():raise Blocked("output-exists")
    fd,tmp=tempfile.mkstemp(prefix=".recover.",dir=target.parent)
    try:
        os.fchmod(fd,0o400)
        with os.fdopen(fd,"wb") as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
        fd=-1;os.link(tmp,target)
        directory_fd=os.open(target.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(directory_fd)
        finally:os.close(directory_fd)
    except FileExistsError as exc:raise Blocked("output-exists") from exc
    finally:
        if fd>=0:os.close(fd)
        try:os.unlink(tmp)
        except FileNotFoundError:pass
def publish(path,data):
    target=pathlib.Path(path)
    if target.exists() or target.is_symlink():
        mode=stat.S_IMODE(target.stat().st_mode) if target.is_file() and not target.is_symlink() else None
        if mode==0o400 and target.read_bytes()==data:return
        raise Blocked("output-exists")
    try:write_once(target,data)
    except Blocked:
        if not target.is_file() or target.is_symlink() or stat.S_IMODE(target.stat().st_mode)!=0o400 or target.read_bytes()!=data:raise
def validate(current,envelope,result,core_paths,diagnostic_paths,terminal_paths):
    if not isinstance(current,dict) or current.get("version")!=3 or "probe_evidence" not in current:raise Blocked("observation-schema")
    exact(current["probe_evidence"],PROBE_FIELDS,"probe-evidence")
    if not all(valid_hash(value) for value in current["probe_evidence"].values()):raise Blocked("probe-evidence-schema")
    exact(envelope,{"manifest","manifest_sha256"},"manifest-envelope")
    manifest=envelope["manifest"];exact(manifest,MANIFEST_FIELDS,"manifest")
    if digest(manifest)!=envelope["manifest_sha256"] or not valid_hash(envelope["manifest_sha256"]):raise Blocked("manifest-binding")
    if manifest["version"]!=4 or manifest["mode"]!="approved-outage-drill" or manifest["resources"]!=["adguard-exporter","adguard"]:raise Blocked("manifest-contract")
    exact(manifest["probe_evidence"],PROBE_FIELDS,"manifest-probe-evidence")
    if not all(valid_hash(value) for value in manifest["probe_evidence"].values()):raise Blocked("manifest-probe-evidence")
    exact(result,RESULT_FIELDS,"result")
    if result["version"]!=4 or result["status"]!="passed" or result["original_failure_rc"]!=0 or result["recovery_failed"] is not False or result["manifest_sha256"]!=envelope["manifest_sha256"]:raise Blocked("result-binding")
    required_hashes=("manifest_sha256","core_results_sha256","core_partial_results_sha256","outage_results_sha256","partial_outage_results_sha256","postrestore_results_sha256","shared_nonce_sha256")
    if not all(valid_hash(result[key]) for key in required_hashes):raise Blocked("result-schema")
    exact(result["diagnostic_evidence"],{"rows","status"},"diagnostic-evidence");exact(result["postrestore_evidence"],{"rows","status"},"postrestore-evidence")
    if result["core_evidence"]!={"rows":24,"status":"complete"} or result["core_row_count"]!=24 or result["postrestore_evidence"].get("status")!="complete" or result["postrestore_evidence"].get("rows")!=result["postrestore_row_count"] or result["postrestore_row_count"]<=0 or result["postrestore_status"]!="complete":raise Blocked("core-result")
    if len(core_paths)!=4:raise Blocked("core-rows")
    rows=[]
    for worker,path in enumerate(core_paths,1):
        try:file_rows=pathlib.Path(path).read_text().splitlines()
        except (OSError,UnicodeError) as exc:raise Blocked("core-rows") from exc
        if len(file_rows)!=6 or any(not row.startswith(f"{worker:02d}:") for row in file_rows):raise Blocked("core-rows")
        rows.extend(file_rows)
    matches=[parse_row(row) for row in rows]
    if len(rows)!=24 or any(match is None for match in matches):raise Blocked("core-rows")
    if {(match["ordinal"],match["item"]) for match in matches}!={(f"{worker:02d}",f"{item:02d}") for worker in range(1,5) for item in range(1,7)}:raise Blocked("core-rows")
    expected_core={"01":("system","udp"),"02":("system","tcp"),"03":("192.168.10.230","udp"),"04":("192.168.10.230","tcp")}
    if any((match["resolver"],match["transport"])!=expected_core[match["ordinal"]] for match in matches):raise Blocked("core-rows")
    frozen="\n".join(sorted(rows,key=lambda row:tuple(map(int,row.split(":",2)[:2]))))+"\n"
    core_sha=hashlib.sha256(frozen.encode()).hexdigest()
    if any(result[key]!=core_sha for key in ("core_results_sha256","core_partial_results_sha256","outage_results_sha256","partial_outage_results_sha256")):raise Blocked("core-binding")
    if len(diagnostic_paths)!=2 or len(terminal_paths)!=2:raise Blocked("diagnostic-rows")
    diagnostic_rows=[];terminals=[]
    for worker,(row_path,terminal_path) in enumerate(zip(diagnostic_paths,terminal_paths),1):
        try:file_rows=pathlib.Path(row_path).read_text().splitlines();terminal=load(terminal_path)
        except (OSError,UnicodeError) as exc:raise Blocked("diagnostic-rows") from exc
        parsed=[parse_row(row) for row in file_rows]
        if len(file_rows)>6 or any(row is None or row["ordinal"]!=f"{worker:02d}" or row["transport"]!=("udp" if worker==1 else "tcp") for row in parsed):raise Blocked("diagnostic-rows")
        try:resolvers={str(ipaddress.IPv6Address(row["resolver"])) for row in parsed}
        except ipaddress.AddressValueError as exc:raise Blocked("diagnostic-rows") from exc
        if len(resolvers)>1:raise Blocked("diagnostic-rows")
        exact(terminal,{"ordinal","rc_class","resolver_label","row_count","status","transport"},"diagnostic-terminal")
        expected_status="complete" if terminal["rc_class"]=="success" and len(file_rows)==6 else "cancelled" if terminal["rc_class"]=="cancelled" else "failed" if not file_rows else "partial"
        if terminal!={"ordinal":worker,"rc_class":terminal["rc_class"],"resolver_label":"gateway-rdnss","row_count":len(file_rows),"status":expected_status,"transport":("udp" if worker==1 else "tcp")} or terminal["rc_class"] not in {"success","cancelled","failed"}:raise Blocked("diagnostic-terminal")
        diagnostic_rows.extend(file_rows);terminals.append(terminal)
    diagnostic_rows.sort(key=lambda row:tuple(map(int,row.split(":",2)[:2])))
    diagnostic_evidence="\n".join(diagnostic_rows)
    for terminal in terminals:diagnostic_evidence+=canonical(terminal).decode()+"\n"
    diagnostic_sha=hashlib.sha256((diagnostic_evidence+"\n").encode()).hexdigest()
    if diagnostic_sha!=EXPECTED_DIAGNOSTIC_RESULTS_SHA256:raise Blocked("diagnostic-identity")
    complete=all(terminal["status"]=="complete" for terminal in terminals) and len(diagnostic_rows)==12
    status="complete" if complete else "partial"
    if result["diagnostic_row_count"]!=len(diagnostic_rows) or result["diagnostic_evidence"]!={"rows":len(diagnostic_rows),"status":status} or result["diagnostic_status"]!=status or result["partial_diagnostic_results_sha256"]!=diagnostic_sha or result["diagnostic_results_sha256"]!=(diagnostic_sha if complete else None):raise Blocked("diagnostic-binding")
    return manifest,core_sha,diagnostic_sha
def validate_journal(path,manifest_sha):
    try:rows=[json.loads(line) for line in pathlib.Path(path).read_text().splitlines()]
    except (OSError,UnicodeError,json.JSONDecodeError) as exc:raise Blocked("journal-schema") from exc
    if not rows:raise Blocked("journal-schema")
    for row in rows:
        exact(row,{"event","manifest_sha256","status","version"},"journal")
        if row["version"]!=1 or row["manifest_sha256"]!=manifest_sha:raise Blocked("journal-binding")
    pairs=[(row["event"],str(row["status"])) for row in rows]
    if pairs[:len(PREFIX)]!=PREFIX or pairs[-3:]!=[("recovery-outcome","restored"),("postrestore-checks","started"),("postrestore-checks","passed")]:raise Blocked("journal-contract")
    middle=pairs[len(PREFIX):-3];expected_attempt=1
    while middle:
        event,status=middle.pop(0)
        if (event,status)!=("recovery-attempt",str(expected_attempt)):raise Blocked("journal-contract")
        expected_attempt+=1
        if middle and middle[0][0]=="recovery-outcome":
            _,outcome=middle.pop(0)
            if outcome not in {"start-adguard-failed","health-failed","start-exporter-failed","exporter-readiness-failed","identity-failed"}:raise Blocked("journal-contract")
    if expected_attempt==1 or expected_attempt>4:raise Blocked("journal-contract")
def recover(current_path,manifest_path,result_path,journal_path,preserved_path,recovered_path,core_paths,diagnostic_paths,terminal_paths):
    try:current_raw=pathlib.Path(current_path).read_bytes()
    except OSError as exc:raise Blocked("invalid-input") from exc
    current=parse(current_raw);envelope=load(manifest_path);result=load(result_path)
    if digest(current)!=EXPECTED_CURRENT_OBSERVATION_SHA256:raise Blocked("current-observation-identity")
    if envelope.get("manifest_sha256")!=EXPECTED_MANIFEST_SHA256:raise Blocked("manifest-identity")
    manifest,core_sha,diagnostic_sha=validate(current,envelope,result,core_paths,diagnostic_paths,terminal_paths);validate_journal(journal_path,envelope["manifest_sha256"])
    recovered=dict(current);recovered["probe_evidence"]=manifest["probe_evidence"]
    if {key for key in current if current.get(key)!=recovered.get(key)}!={"probe_evidence"}:raise Blocked("replacement-scope")
    recovered_sha=digest(recovered)
    if recovered_sha!=manifest["inventory_sha256"] or recovered_sha!=EXPECTED_RECOVERED_INVENTORY_SHA256:raise Blocked("recovered-binding")
    outputs=(pathlib.Path(preserved_path),pathlib.Path(recovered_path))
    if outputs[0]==outputs[1]:raise Blocked("output-exists")
    publish(outputs[0],current_raw);publish(outputs[1],canonical(recovered)+b"\n")
    return {"core_results_sha256":core_sha,"diagnostic_row_count":result["diagnostic_row_count"],"diagnostic_status":result["diagnostic_status"],"manifest_sha256":envelope["manifest_sha256"],"partial_diagnostic_results_sha256":diagnostic_sha,"recovered_inventory_sha256":recovered_sha,"status":"recovered","version":1}
def main(argv):
    if len(argv)!=15:raise Blocked("arguments")
    report=recover(*argv[1:7],argv[7:11],argv[11:13],argv[13:15]);print(json.dumps(report,sort_keys=True,separators=(",",":")))
if __name__=="__main__":
    try:main(sys.argv)
    except Blocked as exc:print("p3-observation-recover: BLOCKED: "+str(exc),file=sys.stderr);raise SystemExit(1)
