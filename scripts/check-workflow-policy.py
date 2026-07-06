#!/usr/bin/env python3
"""Enforce baseline safety policy for GitHub Actions workflows."""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKFLOW_DIR = ROOT / ".github" / "workflows"
MAX_TIMEOUT_MINUTES = 360
EXPECTED_PERMISSIONS = {
    "release.yml": {"contents": "write"},
}
DEFAULT_PERMISSIONS = {"contents": "read"}


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def load_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{rel(path)} must contain a YAML mapping")
    return data


def workflow_paths(args: list[str]) -> list[Path]:
    if not args:
        args = [str(DEFAULT_WORKFLOW_DIR)]

    paths: list[Path] = []
    for arg in args:
        path = Path(arg)
        if not path.is_absolute():
            path = ROOT / path
        if path.is_dir():
            paths.extend(sorted(path.glob("*.yml")))
            paths.extend(sorted(path.glob("*.yaml")))
        else:
            paths.append(path)
    return sorted(set(paths))


def check_permissions(path: Path, data: dict[str, Any]) -> list[str]:
    permissions = data.get("permissions")
    if not isinstance(permissions, dict) or not permissions:
        return [f"{rel(path)} must declare non-empty top-level permissions"]

    problems: list[str] = []
    for scope, level in permissions.items():
        if not isinstance(scope, str) or not isinstance(level, str):
            problems.append(f"{rel(path)} permissions entries must be string keys/values")
        elif level not in {"read", "write", "none"}:
            problems.append(
                f"{rel(path)} permission {scope!r} has unsupported level {level!r}"
            )
    expected = EXPECTED_PERMISSIONS.get(path.name, DEFAULT_PERMISSIONS)
    if permissions != expected:
        problems.append(
            f"{rel(path)} permissions must be {expected}, got {permissions}"
        )
    return problems


def check_jobs(path: Path, data: dict[str, Any]) -> list[str]:
    jobs = data.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return [f"{rel(path)} must define at least one job"]

    problems: list[str] = []
    for job_name, job in jobs.items():
        if not isinstance(job, dict):
            problems.append(f"{rel(path)} job {job_name!r} must be a mapping")
            continue
        timeout = job.get("timeout-minutes")
        if not isinstance(timeout, int):
            problems.append(
                f"{rel(path)} job {job_name!r} must declare integer timeout-minutes"
            )
        elif not 1 <= timeout <= MAX_TIMEOUT_MINUTES:
            problems.append(
                f"{rel(path)} job {job_name!r} timeout-minutes must be 1..{MAX_TIMEOUT_MINUTES}"
            )
    return problems


def main() -> int:
    paths = workflow_paths(sys.argv[1:])
    if not paths:
        print("no GitHub Actions workflow files found", file=sys.stderr)
        return 1

    problems: list[str] = []
    for path in paths:
        try:
            data = load_yaml(path)
        except (OSError, yaml.YAMLError, ValueError) as exc:
            problems.append(str(exc))
            continue
        problems.extend(check_permissions(path, data))
        problems.extend(check_jobs(path, data))

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1

    print(f"verified GitHub Actions workflow policy for {len(paths)} workflow(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
