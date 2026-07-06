#!/usr/bin/env python3
"""Validate a recorded scripts/release-check.sh log."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_MARKERS = (
    ">> formatting",
    ">> linting",
    ">> tests",
    ">> release build",
    ">> local cargo install",
    "verified local cargo install verifier tests",
    "verified local cargo install",
    ">> Crates.io install verifier",
    "verified Crates.io install verifier tests",
    ">> Crates.io metadata",
    "verified crates.io metadata tests",
    "verified crates.io metadata",
    ">> release archive verifier",
    "verified release archive verifier tests",
    "verified release artifact contract tests",
    "verified release artifact contract",
    ">> GitHub release verifier",
    "verified GitHub release verifier tests",
    "verified GitHub release parity verifier tests",
    ">> Bioconda recipe",
    "verified Bioconda recipe tests",
    "verified GitHub source sha256 helper tests",
    ">> Bioconda install verifier",
    "verified Bioconda install verifier tests",
    ">> public install audit verifier",
    "verified public install verifier tests",
    "verified public audit log tests",
    "verified shell script syntax",
    "verified python script syntax",
    "verified release-check contract",
    "verified release-check contract tests",
    "verified release-check log tests",
    "verified repository hygiene ignores",
    "verified directly executable scripts",
    "verified public install audit workflow",
    "verified CI workflow",
    "verified release workflow",
    "verified Crates.io publish workflow",
    "verified GitHub Actions workflow policy",
    "verified workflow policy guard",
    ">> publish ref verifier",
    "verified publish ref tests",
    ">> benchmark summarizer",
    "verified benchmark summarize tests",
    "verified benchmark summary tests",
    ">> parity doc",
    "verified parity doc tests",
    "verified parity doc",
    ">> residual writer",
    "verified residual writer tests",
    ">> version consistency self-test",
    "verified version consistency tests",
    "verified prepare next version tests",
    ">> version consistency",
    ">> release status doc",
    "verified release status doc tests",
    "verified release status doc",
    "verified install docs tests",
    "verified install docs",
    "verified release guide tests",
    "verified release guide",
    "verified release notes tests",
    ">> release readiness verifier",
    "verified release readiness tests",
    "verified release evidence report tests",
    ">> maintainer surfaces",
    "verified maintainer surfaces tests",
    ">> publish ref",
    ">> package file lists",
    "verified package file list tests",
    ">> package gxfkit-core",
    ">> package gxfkit",
    ">> release preflight complete",
    "release-check-exit-code=0",
)
FORBIDDEN_MARKERS = (
    "spurious network error",
    "Timeout was reached",
    "failed to download from",
    "Updating `ustc` index",
)


def parse_version(value: str) -> str:
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", value):
        raise argparse.ArgumentTypeError(f"must look like X.Y.Z, got: {value}")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", type=parse_version, help="expected release version in the log")
    parser.add_argument("log", type=Path, help="captured release-check log")
    return parser.parse_args(argv)


def require_order(text: str, errors: list[str]) -> None:
    offset = -1
    for marker in REQUIRED_MARKERS:
        index = text.find(marker, offset + 1)
        if index == -1:
            errors.append(f"release-check log is missing marker: {marker}")
            continue
        if index < offset:
            errors.append(f"release-check log marker is out of order: {marker}")
        offset = index


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.log.is_file():
        print(f"ERROR release-check log not found: {args.log}", file=sys.stderr)
        return 1

    text = args.log.read_text(encoding="utf-8")
    errors: list[str] = []
    require_order(text, errors)

    for marker in FORBIDDEN_MARKERS:
        if marker in text:
            errors.append(f"release-check log contains forbidden marker: {marker}")

    if "gxfkit package verification passed" not in text and (
        "gxfkit package verification did not complete" not in text
        or "expected before gxfkit-core has been published" not in text
    ):
        errors.append(
            "release-check log must show either successful gxfkit package "
            "verification or the expected pre-public gxfkit-core registry gap"
        )
    exit_codes = re.findall(r"(?m)^release-check-exit-code=(.+)$", text)
    if len(exit_codes) != 1:
        errors.append("release-check log must contain exactly one release-check-exit-code line")
    elif exit_codes[0] != "0":
        errors.append(f"release-check exit code must be 0, got {exit_codes[0]}")

    if args.version is not None:
        if f"gxfkit {args.version}" not in text:
            errors.append(f"release-check log must mention gxfkit {args.version}")
        if f"verified release notes for v{args.version}" not in text:
            errors.append(f"release-check log must verify release notes for v{args.version}")
        if f"OK crate versions: {args.version}" not in text:
            errors.append(f"release-check log must verify crate versions: {args.version}")

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("verified release-check log")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
