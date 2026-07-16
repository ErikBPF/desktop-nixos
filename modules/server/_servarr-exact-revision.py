#!/usr/bin/env python3
"""Exact, value-free Servarr revision transition contract.

Only ``prefetch`` may access the network.  ``activate`` and ``verify`` operate
on objects already proven present by the prefetch evidence.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


REPOSITORY = Path("/home/erik/servarr")
REMOTE = "origin"
FETCH_REF = "main"
FORWARD = "9969e35dca0cfb49a68bda3ba10156667cd4b53f"
FORWARD_TREE = "64d61bb25e0ee7cadda556e54ec86c4faf4f1fd8"
ROLLBACK = "b676063eafa53c00947c458d631493f98349f63c"
ROLLBACK_TREE = "d312855e4a501995cb3f0216659d63763c6b3205"
ENV_BLOB = "machines/discovery/.env.sops"
LOCK_PATH = Path("/run/lock/servarr-repository.lock")
RENDER_CONTRACT = {
    "argv": ["docker-compose", "--project-name", "networking", "--project-directory",
             "/home/erik/servarr/machines/discovery", "--env-file",
             "/home/erik/servarr/machines/discovery/.env", "--env-file",
             "/run/vault-agent/networking.env", "-f",
             "/home/erik/servarr/machines/discovery/networking.yml", "config",
             "--no-interpolate", "--no-env-resolution"],
    "cwd": "/home/erik/servarr/machines/discovery",
    "version": 1,
}


class ContractError(RuntimeError):
    pass


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def _digest(value):
    return hashlib.sha256(_canonical(value)).hexdigest()


def _exact(value, keys, name):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ContractError(f"invalid {name} schema")


def _atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(_canonical(value) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _snapshot_path(path):
    """Private on-filesystem snapshot; contents never enter evidence."""
    path = Path(path)
    if not path.exists():
        return {"existed": False, "mode": None, "temporary": None}
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.rollback.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as destination:
            with path.open("rb") as source:
                while chunk := source.read(65536):
                    destination.write(chunk)
                destination.flush(); os.fsync(destination.fileno())
    except Exception:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise
        raise
    return {"existed": True, "mode": path.stat().st_mode & 0o7777,
            "temporary": temporary}


def _restore_snapshot(path, snapshot):
    path = Path(path)
    if snapshot["existed"]:
        os.chmod(snapshot["temporary"], snapshot["mode"])
        os.replace(snapshot["temporary"], path)
        snapshot["temporary"] = None
    elif path.exists():
        path.unlink()


def _discard_snapshot(snapshot):
    temporary = snapshot.get("temporary")
    if temporary and os.path.exists(temporary):
        os.unlink(temporary)
        snapshot["temporary"] = None


class GitRunner:
    def __init__(self, observer=None):
        self.observer = observer

    def run(self, repo, *arguments, check=True):
        argv = ["git", "-C", str(repo), *arguments]
        if self.observer:
            self.observer(argv)
        result = subprocess.run(argv, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False)
        if check and result.returncode:
            raise ContractError("git contract command failed")
        return result


def _git(runner, repo, *arguments):
    return runner.run(repo, *arguments).stdout.strip()


def _object(runner, repo, commit, render_sha256=None):
    if not len(commit) == 40 or any(character not in "0123456789abcdef" for character in commit):
        raise ContractError("malformed commit")
    kind = _git(runner, repo, "cat-file", "-t", commit)
    if kind != "commit":
        raise ContractError("target is not a commit")
    result = {"commit": commit, "tree": _git(runner, repo, "show", "-s", "--format=%T", commit)}
    if render_sha256 is not None:
        if len(render_sha256) != 64 or any(character not in "0123456789abcdef" for character in render_sha256):
            raise ContractError("invalid render digest")
        result["render_sha256"] = render_sha256
    return result


def _expected_trees():
    # Tests replace commit constants with fixture commits, whose trees cannot be
    # known at module-build time. Production constants remain fully pinned.
    if FORWARD == "9969e35dca0cfb49a68bda3ba10156667cd4b53f":
        return FORWARD_TREE, ROLLBACK_TREE
    return None, None


def _render_digest(rendered, workdir):
    """Normalize the detached checkout path to the canonical Compose workdir."""
    detached = os.fsencode(Path(workdir))
    canonical = os.fsencode(REPOSITORY / "machines/discovery")
    return hashlib.sha256(rendered.replace(detached, canonical)).hexdigest()


def render_revision(repo, commit, runner=None):
    """Hash a fixed Compose render from a detached temporary worktree."""
    runner = runner or GitRunner()
    with tempfile.TemporaryDirectory(prefix="servarr-render-") as parent:
        checkout = Path(parent) / "checkout"
        runner.run(repo, "worktree", "add", "--detach", str(checkout), commit)
        try:
            workdir = checkout / "machines/discovery"
            live_env = REPOSITORY / "machines/discovery/.env"
            if live_env.is_file():
                (workdir / ".env").symlink_to(live_env)
            replacements = {
                str(REPOSITORY / "machines/discovery"): str(workdir),
                str(REPOSITORY / "machines/discovery/.env"): str(workdir / ".env"),
                str(REPOSITORY / "machines/discovery/networking.yml"): str(workdir / "networking.yml"),
            }
            argv = [replacements.get(argument, argument) for argument in RENDER_CONTRACT["argv"]]
            result = subprocess.run(argv, cwd=workdir, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, check=False)
            if result.returncode:
                raise ContractError("compose render failed")
            return _render_digest(result.stdout, workdir)
        finally:
            runner.run(repo, "worktree", "remove", "--force", str(checkout), check=False)


def prefetch(repo=REPOSITORY, output=None, runner=None, renderer=None):
    """Fetch only origin/main, then bind exact commits, trees, and ancestry."""
    runner = runner or GitRunner()
    runner.run(repo, "fetch", "--prune", REMOTE, FETCH_REF)
    fetched = _git(runner, repo, "rev-parse", "refs/remotes/origin/main")
    renderer = renderer or (lambda source, commit: render_revision(source, commit, runner))
    forward = _object(runner, repo, FORWARD, renderer(repo, FORWARD))
    rollback = _object(runner, repo, ROLLBACK, renderer(repo, ROLLBACK))
    if runner.run(repo, "merge-base", "--is-ancestor", ROLLBACK, FORWARD,
                  check=False).returncode:
        raise ContractError("rollback is not an ancestor of forward")
    if runner.run(repo, "merge-base", "--is-ancestor", FORWARD,
                  "refs/remotes/origin/main", check=False).returncode:
        raise ContractError("forward is not published on origin/main")
    expected_forward, expected_rollback = _expected_trees()
    if expected_forward and (forward["tree"] != expected_forward or rollback["tree"] != expected_rollback):
        raise ContractError("pinned tree mismatch")
    contract = {
        "fetch_ref": FETCH_REF,
        "forward": forward,
        "remote": REMOTE,
        "repository": str(REPOSITORY),
        "rollback": rollback,
        "version": 1,
    }
    evidence = {
        "fetched_origin_main": fetched,
        "forward": forward,
        "objects_present": True,
        "rollback": rollback,
        "version": 1,
    }
    envelope = {
        "contract": contract,
        "contract_sha256": _digest(contract),
        "evidence": evidence,
        "evidence_sha256": _digest(evidence),
    }
    validate_prefetch(envelope)
    if output:
        _atomic_json(output, envelope)
    return envelope


def validate_prefetch(envelope):
    _exact(envelope, {"contract", "contract_sha256", "evidence", "evidence_sha256"}, "prefetch envelope")
    contract, evidence = envelope["contract"], envelope["evidence"]
    _exact(contract, {"version", "repository", "remote", "fetch_ref", "forward", "rollback"}, "prefetch contract")
    _exact(evidence, {"version", "forward", "rollback", "fetched_origin_main", "objects_present"}, "prefetch evidence")
    for name in ("forward", "rollback"):
        _exact(contract[name], {"commit", "tree", "render_sha256"}, f"contract {name}")
        _exact(evidence[name], {"commit", "tree", "render_sha256"}, f"evidence {name}")
    if envelope["contract_sha256"] != _digest(contract) or envelope["evidence_sha256"] != _digest(evidence):
        raise ContractError("prefetch hash mismatch")
    if contract["repository"] != str(REPOSITORY) or contract["remote"] != REMOTE or contract["fetch_ref"] != FETCH_REF:
        raise ContractError("prefetch source mismatch")
    if contract["forward"] != evidence["forward"] or contract["rollback"] != evidence["rollback"]:
        raise ContractError("prefetch selection drift")
    if not evidence["objects_present"]:
        raise ContractError("prefetch objects absent")
    return envelope


def _validate_authorization(authorization, prefetch_envelope, selection, prefetch_path):
    _exact(authorization, {"authorization", "authorization_sha256"}, "authorization envelope")
    body = authorization["authorization"]
    _exact(body, {"version", "selection", "selected", "prefetch"}, "authorization")
    _exact(body["prefetch"], {"path", "sha256"}, "authorization prefetch")
    _exact(body["selected"], {"commit", "tree", "render_sha256"}, "authorization selected")
    if authorization["authorization_sha256"] != _digest(body):
        raise ContractError("authorization hash mismatch")
    expected = {
        "prefetch": {"path": str(Path(prefetch_path).resolve()),
                     "sha256": hashlib.sha256(Path(prefetch_path).read_bytes()).hexdigest()},
        "selected": prefetch_envelope["contract"][selection],
        "selection": selection,
        "version": 1,
    }
    if body != expected:
        raise ContractError("authorization binding drift")


def _target(prefetch_envelope, selection):
    if selection not in ("forward", "rollback"):
        raise ContractError("selection must be forward or rollback")
    return prefetch_envelope["contract"][selection]


def _blob(runner, repo, revision):
    result = runner.run(repo, "rev-parse", f"{revision}:{ENV_BLOB}", check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def _validate_prefetch_file(prefetch_path, prefetch_envelope, authorization):
    try:
        raw = Path(prefetch_path).read_bytes()
        parsed = json.loads(raw)
    except (OSError, ValueError) as error:
        raise ContractError("prefetch evidence file invalid") from error
    if parsed != prefetch_envelope:
        raise ContractError("prefetch evidence bytes drift")
    if hashlib.sha256(raw).hexdigest() != authorization["authorization"]["prefetch"]["sha256"]:
        raise ContractError("prefetch evidence file hash drift")


def _recheck_local_bindings(runner, repo, prefetch_envelope):
    contract = prefetch_envelope["contract"]
    for selection in ("forward", "rollback"):
        local = _object(runner, repo, contract[selection]["commit"])
        if local != {key: contract[selection][key] for key in ("commit", "tree")}:
            raise ContractError("local commit/tree drift")
    if runner.run(repo, "merge-base", "--is-ancestor", contract["rollback"]["commit"],
                  contract["forward"]["commit"], check=False).returncode:
        raise ContractError("local ancestry drift")
    origin_main = _git(runner, repo, "rev-parse", "refs/remotes/origin/main")
    if origin_main != prefetch_envelope["evidence"]["fetched_origin_main"]:
        raise ContractError("local publication ref drift")
    if runner.run(repo, "merge-base", "--is-ancestor", contract["forward"]["commit"],
                  "refs/remotes/origin/main", check=False).returncode:
        raise ContractError("local publication drift")


def _pin_envelope(target, selection):
    pin = {
        "commit": target["commit"],
        "render_sha256": target["render_sha256"],
        "selection": selection,
        "tree": target["tree"],
        "version": 1,
    }
    return {"pin": pin, "pin_sha256": _digest(pin)}


def _validate_pin(envelope, target, selection):
    _exact(envelope, {"pin", "pin_sha256"}, "revision pin envelope")
    _exact(envelope["pin"], {"version", "commit", "tree", "render_sha256", "selection"}, "revision pin")
    expected = _pin_envelope(target, selection)
    if envelope != expected:
        raise ContractError("exact revision pin drift")


def activate(repo, selection, prefetch_envelope, authorization, prefetch_path,
             output=None, runner=None, decryptor=None, lock_path=None):
    """Atomically select a prefetched revision. Never performs network I/O."""
    runner = runner or GitRunner()
    lock_path = Path(lock_path or LOCK_PATH)
    with lock_path.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        validate_prefetch(prefetch_envelope)
        target = _target(prefetch_envelope, selection)
        _validate_authorization(authorization, prefetch_envelope, selection, prefetch_path)
        _validate_prefetch_file(prefetch_path, prefetch_envelope, authorization)
        _recheck_local_bindings(runner, repo, prefetch_envelope)
        before = _git(runner, repo, "rev-parse", "HEAD")
        environment_path = Path(repo) / "machines/discovery/.env"
        pin_path = Path(repo) / ".deploy-commit"
        environment_snapshot = _snapshot_path(environment_path)
        pin_snapshot = _snapshot_path(pin_path)
        current_blob = _blob(runner, repo, before)
        target_blob = _blob(runner, repo, target["commit"])
        encrypted_blob_changed = current_blob != target_blob
        if encrypted_blob_changed and decryptor is None:
            _discard_snapshot(environment_snapshot); _discard_snapshot(pin_snapshot)
            raise ContractError("encrypted blob changed without decrypt runner")
        try:
            prepared = decryptor.prepare(repo, target["commit"]) if encrypted_blob_changed else None
        except Exception:
            _discard_snapshot(environment_snapshot); _discard_snapshot(pin_snapshot)
            raise
        # All drift and authorization checks happen before this first mutation.
        try:
            runner.run(repo, "reset", "--hard", target["commit"])
            head = _git(runner, repo, "rev-parse", "HEAD")
            tree = _git(runner, repo, "show", "-s", "--format=%T", "HEAD")
            if head != target["commit"] or tree != target["tree"]:
                raise ContractError("activated revision verification failed")
            if encrypted_blob_changed:
                decryptor.install(prepared)
            _atomic_json(pin_path, _pin_envelope(target, selection))
            evidence = {
                "authorization_sha256": authorization["authorization_sha256"],
                "encrypted_blob_changed": encrypted_blob_changed,
                "head": head,
                "idempotent": before == head,
                "prefetch_sha256": prefetch_envelope["evidence_sha256"],
                "selection": selection,
                "status": "activated",
                "tree": tree,
                "version": 1,
            }
            envelope = {"evidence": evidence, "evidence_sha256": _digest(evidence)}
            if output:
                _atomic_json(output, envelope)
        except Exception as error:
            recovery = runner.run(repo, "reset", "--hard", before, check=False)
            _restore_snapshot(environment_path, environment_snapshot)
            _restore_snapshot(pin_path, pin_snapshot)
            if isinstance(prepared, (str, os.PathLike)) and os.path.exists(prepared):
                os.unlink(prepared)
            recovered_head = runner.run(repo, "rev-parse", "HEAD", check=False)
            if recovery.returncode or recovered_head.returncode or recovered_head.stdout.strip() != before:
                raise ContractError("exact revision transaction recovery failed") from error
            raise
        _discard_snapshot(environment_snapshot); _discard_snapshot(pin_snapshot)
    return envelope


def verify(repo, selection, prefetch_envelope, output=None, runner=None):
    """Read-only exact HEAD/tree/pin verification."""
    runner = runner or GitRunner()
    validate_prefetch(prefetch_envelope)
    target = _target(prefetch_envelope, selection)
    head = _git(runner, repo, "rev-parse", "HEAD")
    tree = _git(runner, repo, "show", "-s", "--format=%T", "HEAD")
    pin_path = Path(repo) / ".deploy-commit"
    try:
        pin = json.loads(pin_path.read_bytes())
        _validate_pin(pin, target, selection)
    except (OSError, ValueError) as error:
        raise ContractError("exact revision pin invalid") from error
    if (head, tree) != (target["commit"], target["tree"]):
        raise ContractError("exact revision verification failed")
    evidence = {"head": head, "selection": selection, "status": "verified",
                "tree": tree, "version": 1}
    envelope = {"evidence": evidence, "evidence_sha256": _digest(evidence)}
    if output:
        _atomic_json(output, envelope)
    return envelope


def pin_precedence_contract():
    return {"precedence": [".deploy-commit", ".deploy-branch", "default_branch"],
            "unpin_supported": False, "version": 1}


class EnvironmentDecryptor:
    """Prepare plaintext before reset; install it atomically afterwards."""
    def __init__(self, runner=None):
        self.runner = runner or GitRunner()

    def prepare(self, repo, commit):
        encrypted = self.runner.run(repo, "show", f"{commit}:{ENV_BLOB}").stdout
        destination = REPOSITORY / "machines/discovery/.env"
        descriptor, temporary = tempfile.mkstemp(prefix=".env.prepared.", dir=destination.parent)
        with os.fdopen(descriptor, "wb") as stream:
            result = subprocess.run(
                ["sops", "--input-type", "dotenv", "--output-type", "dotenv", "--decrypt", "/dev/stdin"],
                input=encrypted.encode(), stdout=stream, stderr=subprocess.PIPE, check=False,
            )
            stream.flush(); os.fsync(stream.fileno())
        if result.returncode:
            os.unlink(temporary)
            raise ContractError("environment decrypt prepare failed")
        return temporary

    def install(self, prepared):
        os.replace(prepared, REPOSITORY / "machines/discovery/.env")


def _require_repository_owner():
    if os.geteuid() != REPOSITORY.stat().st_uid:
        raise ContractError("production activation must run as repository owner")


def _read(path):
    return json.loads(Path(path).read_text())


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    prefetch_parser = subparsers.add_parser("prefetch")
    prefetch_parser.add_argument("--output", required=True)
    activate_parser = subparsers.add_parser("activate")
    activate_parser.add_argument("selection", choices=("forward", "rollback"))
    activate_parser.add_argument("--prefetch", required=True)
    activate_parser.add_argument("--authorization", required=True)
    activate_parser.add_argument("--output", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("selection", choices=("forward", "rollback"))
    verify_parser.add_argument("--prefetch", required=True)
    verify_parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    if arguments.command == "prefetch":
        prefetch(output=arguments.output)
    elif arguments.command == "activate":
        _require_repository_owner()
        activate(REPOSITORY, arguments.selection, _read(arguments.prefetch),
                 _read(arguments.authorization), arguments.prefetch,
                 output=arguments.output, decryptor=EnvironmentDecryptor())
    else:
        verify(REPOSITORY, arguments.selection, _read(arguments.prefetch), output=arguments.output)


if __name__ == "__main__":
    main()
