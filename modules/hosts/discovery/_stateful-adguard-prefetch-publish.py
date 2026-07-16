#!/usr/bin/env python3
"""Root-controlled atomic publisher for the fixed P2 revision prefetch."""
import hashlib,json,os,pathlib,pwd,re,stat,sys
PENDING=pathlib.Path("/home/erik/.cache/stateful-stack-migrations/p2-adguard/revision-prefetch.json.pending")
DIRECTORY=pathlib.Path("/var/lib/stateful-stack-migrations/p2-adguard");STAGING=DIRECTORY/".revision-prefetch.json.publish";FINAL=DIRECTORY/"revision-prefetch.json"
FORWARD="9969e35dca0cfb49a68bda3ba10156667cd4b53f";FORWARD_TREE="64d61bb25e0ee7cadda556e54ec86c4faf4f1fd8";ROLLBACK="b676063eafa53c00947c458d631493f98349f63c";ROLLBACK_TREE="d312855e4a501995cb3f0216659d63763c6b3205";MAX_BYTES=65536
HEX40=re.compile(r"^[0-9a-f]{40}$");HEX64=re.compile(r"^[0-9a-f]{64}$")
class PublishError(RuntimeError):pass
def canonical(value):return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def exact(value,keys):
    if not isinstance(value,dict) or set(value)!=set(keys):raise PublishError("schema differs")
def validate(raw):
    try:value=json.loads(raw)
    except (UnicodeDecodeError,json.JSONDecodeError) as error:raise PublishError("JSON invalid") from error
    exact(value,{"contract","contract_sha256","evidence","evidence_sha256"});contract=value["contract"];evidence=value["evidence"]
    exact(contract,{"version","repository","remote","fetch_ref","forward","rollback"});exact(evidence,{"version","forward","rollback","fetched_origin_main","objects_present"})
    for selected in (contract["forward"],contract["rollback"],evidence["forward"],evidence["rollback"]):exact(selected,{"commit","tree","render_sha256"})
    strings=(value["contract_sha256"],value["evidence_sha256"],contract["repository"],contract["remote"],contract["fetch_ref"],evidence["fetched_origin_main"])+tuple(selected[key] for selected in (contract["forward"],contract["rollback"],evidence["forward"],evidence["rollback"]) for key in ("commit","tree","render_sha256"))
    if any(type(item) is not str for item in strings) or type(contract["version"]) is not int or type(evidence["version"]) is not int:raise PublishError("types differ")
    if contract["version"]!=1 or evidence["version"]!=1 or contract["repository"]!="/home/erik/servarr" or contract["remote"]!="origin" or contract["fetch_ref"]!="main" or evidence["objects_present"] is not True:raise PublishError("fixed contract differs")
    if contract["forward"]["commit"]!=FORWARD or contract["forward"]["tree"]!=FORWARD_TREE or contract["rollback"]["commit"]!=ROLLBACK or contract["rollback"]["tree"]!=ROLLBACK_TREE or evidence["fetched_origin_main"]!=FORWARD:raise PublishError("revision identity differs")
    for selected in (contract["forward"],contract["rollback"],evidence["forward"],evidence["rollback"]):
        if not HEX40.fullmatch(selected["commit"]) or not HEX40.fullmatch(selected["tree"]) or not HEX64.fullmatch(selected["render_sha256"]):raise PublishError("revision format differs")
    if not HEX64.fullmatch(value["contract_sha256"]) or not HEX64.fullmatch(value["evidence_sha256"]):raise PublishError("digest format differs")
    if raw!=canonical(value)+b"\n" or value["contract_sha256"]!=hashlib.sha256(canonical(contract)).hexdigest() or value["evidence_sha256"]!=hashlib.sha256(canonical(evidence)).hexdigest() or contract["forward"]!=evidence["forward"] or contract["rollback"]!=evidence["rollback"]:raise PublishError("binding differs")
    return raw
def read_once(path,uid,gid,hook):
    flags=os.O_RDONLY|os.O_CLOEXEC|getattr(os,"O_NOFOLLOW",0)
    try:descriptor=os.open(path,flags)
    except OSError as error:raise PublishError("pending open failed") from error
    try:
        metadata=os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid!=uid or metadata.st_gid!=gid or stat.S_IMODE(metadata.st_mode)!=0o600 or metadata.st_size<=0 or metadata.st_size>MAX_BYTES:raise PublishError("pending metadata differs")
        hook("after-open");chunks=[]
        while chunk:=os.read(descriptor,65536):chunks.append(chunk)
        return validate(b"".join(chunks))
    finally:os.close(descriptor)
def _publish(pending,staging,final,directory,uid,gid,hook=None):
    pending=pathlib.Path(pending);staging=pathlib.Path(staging);final=pathlib.Path(final);directory=pathlib.Path(directory)
    hook=hook or (lambda stage:None)
    if staging.exists() or final.exists():raise PublishError("retained path exists")
    raw=read_once(pending,uid,gid,hook);created=False;descriptor=-1
    try:
        try:descriptor=os.open(staging,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_CLOEXEC|getattr(os,"O_NOFOLLOW",0),0o600);created=True
        except OSError as error:raise PublishError("staging create failed") from error
        os.fchmod(descriptor,0o600);offset=0
        while offset<len(raw):offset+=os.write(descriptor,raw[offset:])
        os.fsync(descriptor);os.close(descriptor);descriptor=-1;hook("after-staging-write")
        try:os.link(staging,final,follow_symlinks=False)
        except OSError as error:raise PublishError("final publish failed") from error
        hook("after-link");os.unlink(staging);created=False;hook("after-unlink")
        directory_fd=os.open(directory,os.O_RDONLY|os.O_CLOEXEC|getattr(os,"O_DIRECTORY",0))
        try:os.fsync(directory_fd)
        finally:os.close(directory_fd)
    finally:
        if descriptor>=0:os.close(descriptor)
        if created:
            try:os.unlink(staging)
            except FileNotFoundError:pass
def main(argv=None):
    if (argv if argv is not None else sys.argv[1:]) or os.geteuid()!=0:print("discovery-stateful-adguard-prefetch-publish: BLOCKED: PublishError",file=sys.stderr);return 1
    account=pwd.getpwnam("erik")
    try:_publish(PENDING,STAGING,FINAL,DIRECTORY,account.pw_uid,account.pw_gid)
    except (OSError,ValueError,KeyError,PublishError):print("discovery-stateful-adguard-prefetch-publish: BLOCKED: PublishError",file=sys.stderr);return 1
    return 0
if __name__=="__main__":raise SystemExit(main())
