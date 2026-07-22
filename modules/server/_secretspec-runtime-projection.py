#!/usr/bin/env python3
"""Build atomic, value-silent SecretSpec and Compose dotenv projections."""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import stat
import sys
import tempfile
import time
import tomllib


NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class ProjectionError(ValueError):
    pass


def parse_dotenv(path: pathlib.Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    try:
        text = path.read_text()
    except OSError as error:
        raise ProjectionError(f"cannot read dotenv input: {path}") from error
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise ProjectionError(f"malformed dotenv declaration: {path}:{number}")
        name, value = line.split("=", 1)
        if not NAME.fullmatch(name):
            raise ProjectionError(f"invalid dotenv name: {path}:{number}")
        if not value.strip():
            raise ProjectionError(f"empty dotenv value: {path}:{number}")
        rows.append((name, f"{name}={value}"))
    return rows


def write_private(path: pathlib.Path, content: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        raise


def atomic_publish(output_dir: pathlib.Path, provider: str, config: str) -> None:
    output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(output_dir, 0o700)
    generation = pathlib.Path(tempfile.mkdtemp(prefix=".generation-", dir=output_dir))
    current_tmp = output_dir / f".current-{os.getpid()}"
    published = False
    try:
        os.chmod(generation, 0o700)
        write_private(generation / "provider.env", provider)
        write_private(generation / "config.env", config)
        directory_fd = os.open(generation, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        os.symlink(generation.name, current_tmp)
        os.replace(current_tmp, output_dir / "current")
        published = True
        for old in output_dir.glob(".generation-*"):
            if old != generation and old.is_dir():
                try:
                    for child in old.iterdir():
                        child.unlink()
                    old.rmdir()
                except OSError:
                    pass
    except BaseException:
        try:
            current_tmp.unlink()
        except FileNotFoundError:
            pass
        if not published and generation.exists():
            for child in generation.iterdir():
                child.unlink()
            generation.rmdir()
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--legacy-env", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, action="append", required=True)
    parser.add_argument("--source-config-name", action="append", default=[])
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument("--max-age-seconds", type=int, default=900)
    args = parser.parse_args()

    try:
        with args.manifest.open("rb") as handle:
            manifest = tomllib.load(handle)
        expected = manifest["profiles"][args.profile]
        if not isinstance(expected, list) or not expected or any(
            not isinstance(name, str) or not NAME.fullmatch(name) for name in expected
        ):
            raise ProjectionError("invalid or empty SecretSpec profile")
        expected_names = set(expected)
        if len(expected_names) != len(expected):
            raise ProjectionError("duplicate SecretSpec profile name")
        source_config_names = set(args.source_config_name)
        if len(source_config_names) != len(args.source_config_name) or any(
            not NAME.fullmatch(name) for name in source_config_names
        ):
            raise ProjectionError("invalid or duplicate source config name")
        if expected_names & source_config_names:
            raise ProjectionError("source config overlaps SecretSpec profile")
        allowed_names = expected_names | source_config_names

        now = time.time()
        merged: dict[str, str] = {}
        for source in args.source:
            try:
                source_stat = source.stat()
            except OSError as error:
                raise ProjectionError(f"cannot stat dotenv input: {source}") from error
            if not stat.S_ISREG(source_stat.st_mode):
                raise ProjectionError(f"dotenv input is not a regular file: {source}")
            if args.max_age_seconds < 1 or now - source_stat.st_mtime > args.max_age_seconds:
                raise ProjectionError(f"stale dotenv input: {source}")
            for name, row in parse_dotenv(source):
                if name in merged and merged[name] != row:
                    raise ProjectionError(f"conflicting duplicate dotenv name: {name}")
                merged[name] = row

        actual_names = set(merged)
        if actual_names != allowed_names:
            missing = sorted(allowed_names - actual_names)
            extra = sorted(actual_names - allowed_names)
            raise ProjectionError(
                f"provider name closure differs (missing={','.join(missing) or '-'}; "
                f"extra={','.join(extra) or '-'})"
            )

        legacy_lines = args.legacy_env.read_text().splitlines()
        config_lines: list[str] = []
        for number, raw in enumerate(legacy_lines, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                config_lines.append(raw)
                continue
            declaration = line[7:].lstrip() if line.startswith("export ") else line
            if "=" not in declaration:
                raise ProjectionError(f"malformed legacy dotenv declaration: {args.legacy_env}:{number}")
            name = declaration.split("=", 1)[0]
            if not NAME.fullmatch(name):
                raise ProjectionError(f"invalid legacy dotenv name: {args.legacy_env}:{number}")
            if name not in allowed_names:
                config_lines.append(raw)

        config_lines.extend(merged[name] for name in sorted(source_config_names))

        provider = "\n".join(merged[name] for name in sorted(expected_names)) + "\n"
        config = "\n".join(config_lines) + "\n"
        atomic_publish(args.output_dir, provider, config)
        print(
            f"projection=ready profile={args.profile} names={len(expected_names)} "
            f"source_config_names={len(source_config_names)}"
        )
    except (OSError, KeyError, TypeError, ProjectionError, tomllib.TOMLDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
