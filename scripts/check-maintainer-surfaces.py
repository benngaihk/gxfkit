#!/usr/bin/env python3
"""Check maintainer-facing templates and manual workflows use current versions."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def workspace_version() -> str:
    text = read("Cargo.toml")
    match = re.search(
        r"(?ms)^\[workspace\.package\]\s+.*?^version\s*=\s*\"([^\"]+)\"",
        text,
    )
    if not match:
        raise SystemExit("could not find [workspace.package] version in Cargo.toml")
    return match.group(1)


def require(text: str, needle: str, label: str, errors: list[str]) -> None:
    if needle not in text:
        errors.append(f"{label} must contain: {needle}")


def forbid(text: str, needle: str, label: str, errors: list[str]) -> None:
    if needle in text:
        errors.append(f"{label} must not contain stale example: {needle}")


def main() -> int:
    version = workspace_version()
    old_bug_example = "gxfkit 0.0.1"
    expected_bug_example = f"gxfkit {version}"
    expected_workflow_example = f"for example {version}"
    expected_tag_example = f"for example v{version}"
    errors: list[str] = []

    issue_templates = [
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/bug_report_zh.yml",
        ".github/ISSUE_TEMPLATE/parity_divergence.yml",
        ".github/ISSUE_TEMPLATE/parity_divergence_zh.yml",
    ]
    for path in issue_templates:
        text = read(path)
        require(text, expected_bug_example, path, errors)
        if version != "0.0.1":
            forbid(text, old_bug_example, path, errors)

    publish_workflow = read(".github/workflows/publish-crates.yml")
    release_workflow = read(".github/workflows/release.yml")
    require(publish_workflow, expected_workflow_example, ".github/workflows/publish-crates.yml", errors)
    require(release_workflow, expected_tag_example, ".github/workflows/release.yml", errors)
    if version != "0.0.1":
        forbid(publish_workflow, "for example 0.0.1", ".github/workflows/publish-crates.yml", errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print(f"verified maintainer surfaces for {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
