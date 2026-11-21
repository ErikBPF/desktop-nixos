"""Explicit, operator-invoked synthetic pilot actions; never scheduled."""
import argparse
from contextlib import ExitStack
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import time
import uuid

spec = importlib.util.spec_from_file_location("integrity_run", Path(__file__).with_name("_host-integrity-run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def locked(stack, path):
    stream = stack.enter_context(os.fdopen(os.open(path, os.O_CREAT | os.O_RDWR, 0o600), "w"))
    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)


def private_json(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.geteuid() or info.st_size > 16 * 1024 * 1024:
            raise ValueError("review evidence must be a restricted owner-only regular file")
        return json.load(stream)


def resolve(cfg, expected_digest, review):
    r = runner.reporter(cfg)
    if cfg["check"] != "av" or set(review) != {"reviewer", "reason", "incidentReceipt", "recoveryReceipt"} or any(
        not isinstance(value, str) or not value.strip() or len(value) > 4096 for value in review.values()
    ):
        raise ValueError("explicit synthetic AV review is required")
    with ExitStack() as stack:
        locked(stack, Path(cfg["state_dir"]) / "av.run.lock")
        locked(stack, r.state_path.with_suffix(".lock"))
        raw = r.state_path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected_digest:
            raise ValueError("reviewed state changed; inspect it again")
        state = r._load(time.time())
        if state["state"] not in (2, 3) or state["errors"] or state["findings"] <= 0:
            raise ValueError("resolution needs a stopped, error-free recovery attempt")
        directory = Path(cfg["state_dir"]) / "receipts"
        for key in ("incidentReceipt", "recoveryReceipt"):
            if Path(review[key]).name != review[key] or not review[key].startswith("av-"):
                raise ValueError("receipt reference must name this check's private receipt")
        incident = private_json(directory / review["incidentReceipt"])
        recovery = private_json(directory / review["recoveryReceipt"])
        if any(record.get("instance") != cfg["instance"] or record.get("check") != "av" for record in (incident, recovery)):
            raise ValueError("receipt identity mismatch")
        if incident.get("commandPolicy", {}).get("synthetic") is not True or incident.get("counts", {}).get("findings") != state["findings"]:
            raise ValueError("only the exact synthetic finding may be resolved")
        if recovery.get("commandPolicy", {}).get("synthetic") or recovery.get("scopeId") != cfg["scopeId"] or recovery.get("started") != state["last_attempt_seconds"] or recovery.get("state") not in ("complete", "partial") or recovery.get("counts", {}).get("findings") != 0 or recovery.get("counts", {}).get("errors") != 0 or recovery["started"] <= incident["started"]:
            raise ValueError("a matching normal zero-finding recovery receipt is required")
        if os.path.lexists(r.state_path.with_name("av.genuine-findings.json")):
            raise ValueError("genuine-finding evidence requires separate resolution outside this pilot")
        for path in directory.glob("av-*.json"):
            record = private_json(path)
            if record.get("started", 0) >= incident["started"] and not record.get("commandPolicy", {}).get("synthetic") and record.get("counts", {}).get("findings", 0) > 0:
                raise ValueError("a genuine finding or ambiguous failure needs separate review")
        audit = dict(schemaRevision=1, instance=cfg["instance"], check="av", action="synthetic-resolution-authorized",
                     expectedStateSha256=expected_digest, before=state.copy(), review=review,
                     reviewedAt=time.time(), priorFindingResolved=True)
        runner.report.atomic_write(directory / f"av-resolution-{uuid.uuid4().hex}.json", json.dumps(audit) + "\n", 0o600)
        state["findings"] = 0
        return r._publish(state, time.time())


def canary(cfg, case):
    if cfg["check"] != "av" or case not in ("finding", "partial", "error"):
        raise ValueError("unsupported synthetic AV canary")
    r = runner.reporter(cfg)
    with ExitStack() as stack:
        locked(stack, Path(cfg["state_dir"]) / "av.run.lock")
        if cfg.get("coordinationLock"):
            locked(stack, Path(cfg["coordinationLock"]))
        locked(stack, Path(cfg["state_dir"]) / "heavy.run.lock")
        previous = r._load(time.time())
        if previous["findings"]:
            raise ValueError("review the retained finding before another canary")
        if os.path.lexists(r.state_path.with_name("av.genuine-findings.json")):
            raise ValueError("genuine-finding evidence blocks synthetic canaries")
        started = time.time()
        r.update("begin", now=started)
        counts = dict(findings=0, skipped=1, errors=0)
        details = [{"synthetic": True, "case": case, "coverage": "not the declared Downloads scope"}]
        Path(cfg["work_dir"]).mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            with tempfile.TemporaryDirectory(prefix="pilot-", dir=cfg["work_dir"]) as temporary:
                directory = Path(temporary)
                marker = b"homelab-integrity-harmless-fixture"
                database = directory / "fixture.ndb"
                database.write_text("HostIntegrityPilot:0:*:" + marker.hex() + "\n")
                (directory / "0").write_bytes(b"harmless clean partial-scope fixture" if case == "partial" else marker)
                listing = directory / "files.txt"
                listing.write_text(str(directory / "0") + "\n")
                command = [arg for arg in cfg["command"] if not arg.startswith("--max-filesize=")]
                command += ["--max-filesize=1048576",
                            f'--database={database if case != "error" else directory / "absent.ndb"}', f"--file-list={listing}"]
                def observed(line):
                    if line.endswith("HostIntegrityPilot.UNOFFICIAL FOUND"):
                        counts["findings"] = 1
                        r.update("progress", finding_source="synthetic", **counts)
                code, output = runner.command(command, time.monotonic() + cfg["timeoutSeconds"], cfg, observed)
                details.append(output)
                if case == "finding" and not (code == 1 and counts["findings"] == 1):
                    counts["errors"] += 1
                elif case == "partial" and not (code == 0 and counts["findings"] == 0):
                    counts["errors"] += 1
                elif case == "error":
                    counts["errors"] += 1
        except (OSError, ValueError) as error:
            counts["errors"] += 1
            details.append(type(error).__name__)
        result = "failed" if counts["errors"] else "partial"
        synthetic = dict(cfg, synthetic=True, scopeId="pilot-synthetic-v1")
        runner.receipt(synthetic, started, result, counts, "pinned-config-command", None, details)
        return r.update(result, finding_source="synthetic", **counts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "canary", "resolve"))
    parser.add_argument("--config", required=True)
    parser.add_argument("--case", choices=("finding", "partial", "error"))
    parser.add_argument("--expected-state-sha256")
    parser.add_argument("--review-file")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("pilot operations require an explicit root invocation")
    cfg = json.loads(Path(args.config).read_text())
    if args.action == "resolve":
        if not args.review_file or not args.expected_state_sha256:
            parser.error("resolve requires reviewed evidence and exact state digest")
        resolve(cfg, args.expected_state_sha256, private_json(args.review_file))
    elif args.action == "canary":
        canary(cfg, args.case)
    else:
        raw = (Path(cfg["state_dir"]) / f'{cfg["check"]}.json').read_bytes()
        print(json.dumps(dict(state=json.loads(raw), state_sha256=hashlib.sha256(raw).hexdigest())))
