#!/usr/bin/env python3
"""Pure exact-revision contract for the P2 AdGuard transition."""
import re

HEX64=re.compile(r"^[0-9a-f]{64}$")
COMMITS={"forward":"9969e35dca0cfb49a68bda3ba10156667cd4b53f","rollback":"b676063eafa53c00947c458d631493f98349f63c"}
TREES={"forward":"64d61bb25e0ee7cadda556e54ec86c4faf4f1fd8","rollback":"d312855e4a501995cb3f0216659d63763c6b3205"}
PREFETCH_PATH="/var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json"

class Drift(ValueError):pass
def validate(value,prefetch_path=PREFETCH_PATH):
    if not isinstance(value,dict) or set(value)!={"forward","prefetch","rollback"}:raise Drift("revision contract fields differ")
    for channel in ("forward","rollback"):
        item=value[channel]
        if not isinstance(item,dict) or set(item)!={"commit","render_sha256","tree"}:raise Drift(f"{channel} revision fields differ")
        if item["commit"]!=COMMITS[channel] or item["tree"]!=TREES[channel] or not HEX64.fullmatch(item["render_sha256"]):raise Drift(f"{channel} revision differs")
    prefetch=value["prefetch"]
    if not isinstance(prefetch,dict) or set(prefetch)!={"path","sha256"} or prefetch["path"]!=prefetch_path or not HEX64.fullmatch(prefetch["sha256"]):raise Drift("revision prefetch differs")
def authorization(channel,value):
    if channel not in ("forward","rollback"):raise Drift("revision channel differs")
    if set(value)!={"forward","prefetch","rollback"} or not HEX64.fullmatch(value["prefetch"].get("sha256", "")):raise Drift("revision authorization input differs")
    body={"prefetch":value["prefetch"],"selected":value[channel],"selection":channel,"version":1}
    import hashlib, json
    sha=hashlib.sha256(json.dumps(body,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()).hexdigest()
    return {"authorization":body,"authorization_sha256":sha}
def activation_argv(channel,value,authorization_path,output,binary="servarr-exact-revision"):
    validate(value,value["prefetch"].get("path"))
    if channel not in ("forward","rollback"):raise Drift("revision channel differs")
    return ["/run/wrappers/bin/sudo","-u","erik","--",binary,"activate",channel,"--prefetch",value["prefetch"]["path"],"--authorization",authorization_path,"--output",output]
