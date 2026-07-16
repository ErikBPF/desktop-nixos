#!/usr/bin/env python3
"""Value-free post-recreate checks for the Discovery AdGuard pair."""

import argparse
import json
import re
import subprocess
import sys
import time


CONTAINERS = ("adguard", "adguard-exporter")
FATAL_LOG_PATTERNS = (
    "fatal",
    "panic",
    "segmentation fault",
    "address already in use",
    "permission denied",
    "read-only file system",
)
IDENTITY_FIELDS = (
    "compose_labels", "compose_project", "compose_service",
    "compose_working_dir", "image_digest", "image_id", "image_ref",
    "mounts", "networks",
)


class ContractError(RuntimeError):
    pass


class DockerLogRunner:
    def run(self, argv):
        result = subprocess.run(argv, check=False, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=30)
        if result.returncode:
            raise ContractError("container log query failed")
        return result.stdout


def _validate_scan_args(containers, since, output, patterns):
    if containers != ",".join(CONTAINERS) or since != "container-start" or output != "counts-only" or patterns != "|".join(FATAL_LOG_PATTERNS):
        raise ContractError("startup scan contract differs")


def startup_fatal_log_scan(containers, since, output, patterns, runner=None):
    _validate_scan_args(containers, since, output, patterns)
    runner = runner or DockerLogRunner()
    compiled = tuple(re.compile(re.escape(pattern), re.IGNORECASE) for pattern in FATAL_LOG_PATTERNS)
    counts = {}
    for name in CONTAINERS:
        started = runner.run(["docker", "inspect", "--format", "{{.State.StartedAt}}", name]).strip()
        if not started or "\n" in started:
            raise ContractError("container start identity invalid")
        logs = runner.run(["docker", "logs", "--since", started, name])
        counts[name] = sum(1 for line in logs.splitlines() if any(pattern.search(line) for pattern in compiled))
    return {
        "containers": list(CONTAINERS),
        "fatal_matches": counts,
        "patterns_checked": len(FATAL_LOG_PATTERNS),
        "raw_logs_retained": False,
        "status": "passed" if all(count == 0 for count in counts.values()) else "fatal",
        "version": 1,
    }


def capture_inventory():
    result = subprocess.run(
        ["discovery-stateful-adguard-inventory", "capture"], check=False,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=30,
    )
    if result.returncode:
        raise ContractError("inventory capture failed")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ContractError("inventory output invalid") from error


def _normalized_baseline(value):
    try:
        api = value["api"]
        result = {
            "api": {key: api[key] for key in (
                "enabled_filter_count", "filter_count", "filtering_enabled",
                "protection_enabled", "query_log_enabled", "rewrite_count",
                "user_rule_count",
            )},
            "dns": {name: {"answered": probe["answer_count"] > 0,
                           "status": probe["status"]}
                    for name, probe in value["dns"].items()},
            "exporter": {key: value["exporter"][key] for key in
                         ("families", "reachable", "required_family_count")},
        }
    except (KeyError, TypeError) as error:
        raise ContractError("baseline schema differs") from error
    return result


def _normalized_point(inventory):
    try:
        containers = {item["name"]: item for item in inventory["containers"]}
        if set(containers) != set(CONTAINERS):
            raise ContractError("container allowlist differs")
        normalized = {}
        ids = []
        for name in CONTAINERS:
            item = containers[name]
            expected_health = "healthy" if name == "adguard" else "none"
            if item["state"] != "running" or item["health"] != expected_health or item["restart_count"] != 0 or not re.fullmatch(r"[0-9a-f]{64}", item["id"]):
                raise ContractError("container runtime differs")
            ids.append(item["id"])
            normalized[name] = {
                "health": item["health"],
                "id": item["id"],
                "identity": {key: item[key] for key in IDENTITY_FIELDS},
                "restart_count": item["restart_count"],
                "state": item["state"],
            }
        if len(set(ids)) != len(CONTAINERS):
            raise ContractError("container identities differ")
        return {"baseline": _normalized_baseline(inventory["baseline"]),
                "containers": normalized}
    except (KeyError, TypeError) as error:
        raise ContractError("inventory schema differs") from error


def _validate_observation_args(containers, duration, interval, baseline,
                               identity, health, restarts, raw_logs):
    expected = (",".join(CONTAINERS), 900, 30, "full-normalized-start-end",
                "exact-new-and-stable", "exact", "zero", "discard")
    if (containers, duration, interval, baseline, identity, health, restarts,
            raw_logs) != expected:
        raise ContractError("stable observation contract differs")


def stable_observation(containers, duration, interval, baseline, identity,
                       health, restarts, raw_logs, *, capture=None, sleep=None,
                       clock=None):
    _validate_observation_args(containers, duration, interval, baseline,
                               identity, health, restarts, raw_logs)
    capture = capture or capture_inventory
    sleep = sleep or time.sleep
    clock = clock or time.monotonic
    started = clock()
    first = None
    last = None
    for index in range(31):
        if index:
            sleep(max(0, started + index * interval - clock()))
        point = _normalized_point(capture())
        if first is None:
            first = point
        elif point != first:
            raise ContractError("stable observation drift")
        last = point
    return {
        "duration_seconds": duration,
        "end": last,
        "raw_logs_retained": False,
        "sample_interval_seconds": interval,
        "samples": 31,
        "start": first,
        "status": "stable",
        "version": 1,
    }


def _parser():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    scan = commands.add_parser("startup-fatal-log-scan")
    scan.add_argument("--containers", required=True)
    scan.add_argument("--since", required=True)
    scan.add_argument("--output", required=True)
    scan.add_argument("--fatal-patterns", required=True)
    stable = commands.add_parser("stable-observation")
    stable.add_argument("--containers", required=True)
    stable.add_argument("--duration-seconds", required=True, type=int)
    stable.add_argument("--sample-interval-seconds", required=True, type=int)
    stable.add_argument("--baseline", required=True)
    stable.add_argument("--identity", required=True)
    stable.add_argument("--health", required=True)
    stable.add_argument("--restarts", required=True)
    stable.add_argument("--raw-logs", required=True)
    return parser


def main(argv=None):
    args = _parser().parse_args(argv)
    try:
        if args.command == "startup-fatal-log-scan":
            result = startup_fatal_log_scan(args.containers, args.since,
                                            args.output, args.fatal_patterns)
            return_code = 0 if result["status"] == "passed" else 1
        else:
            result = stable_observation(
                args.containers, args.duration_seconds,
                args.sample_interval_seconds, args.baseline, args.identity,
                args.health, args.restarts, args.raw_logs,
            )
            return_code = 0
    except (ContractError, OSError, subprocess.SubprocessError):
        print("discovery-stateful-adguard-postcheck: BLOCKED: ContractError",
              file=sys.stderr)
        return 1
    sys.stdout.write(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
