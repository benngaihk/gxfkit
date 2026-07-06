#!/usr/bin/env python3
"""Validate an existing benchmark/results/summary.tsv release evidence table."""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


DEFAULT_SUMMARY = Path("benchmark/results/summary.tsv")
DEFAULT_CORE_FILES = "human_chr1 human_chr21 yeast"
EXPECTED_HEADER = ["file", "agat_s", "gxfkit_s", "speedup", "agat_mem", "gxfkit_mem", "parity%"]
SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def parse_min_parity(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"must be a number, got: {raw}") from exc
    if value < 0 or value > 100:
        raise argparse.ArgumentTypeError(f"must be between 0 and 100, got: {raw}")
    return value


def parse_required_files(raw: str) -> list[str]:
    files = raw.split()
    if not files:
        raise argparse.ArgumentTypeError("must include at least one corpus name")
    seen: set[str] = set()
    for item in files:
        if not SAFE_NAME_RE.fullmatch(item):
            raise argparse.ArgumentTypeError(f"entries must be corpus basenames, got: {item}")
        if item in seen:
            raise argparse.ArgumentTypeError(f"duplicate corpus name: {item}")
        seen.add(item)
    return files


def positive_float(raw: str, label: str, file_name: str, errors: list[str]) -> None:
    try:
        value = float(raw)
    except ValueError:
        errors.append(f"{file_name}: invalid {label}: {raw!r}")
        return
    if value <= 0:
        errors.append(f"{file_name}: {label} must be > 0, got {raw!r}")


def validate(summary: Path, required_files: list[str], min_parity: float, require: bool) -> int:
    if not summary.exists():
        if require:
            print(f"ERROR benchmark summary not found: {summary}", file=sys.stderr)
            return 1
        print(
            "benchmark summary not found; generate with "
            'RUNS=1 BENCH_FILES="human_chr1 human_chr21 yeast" README_OUT= bash benchmark/run.sh'
        )
        return 0

    errors: list[str] = []
    with summary.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames != EXPECTED_HEADER:
            errors.append(
                f"{summary}: unexpected header {reader.fieldnames!r}; expected {EXPECTED_HEADER!r}"
            )
            rows = []
        else:
            rows = list(reader)

    if not rows:
        errors.append(f"{summary}: no benchmark rows")

    seen: set[str] = set()
    parity_by_file: dict[str, float] = {}
    for lineno, row in enumerate(rows, start=2):
        file_name = row.get("file", "")
        if not file_name:
            errors.append(f"{summary}:{lineno}: empty file name")
            continue
        if not SAFE_NAME_RE.fullmatch(file_name):
            errors.append(f"{summary}:{lineno}: unsafe file name {file_name!r}")
            continue
        if file_name in seen:
            errors.append(f"{summary}:{lineno}: duplicate file name {file_name!r}")
            continue
        seen.add(file_name)

        positive_float(row.get("agat_s", ""), "AGAT wall time", file_name, errors)
        positive_float(row.get("gxfkit_s", ""), "gxfkit wall time", file_name, errors)
        speedup = row.get("speedup", "")
        if not speedup.endswith("x") and not speedup.endswith("×"):
            errors.append(f"{file_name}: speedup must end with x/×, got {speedup!r}")
        for label in ("agat_mem", "gxfkit_mem"):
            if not row.get(label, ""):
                errors.append(f"{file_name}: missing {label}")
        raw_parity = row.get("parity%", "")
        try:
            parity = float(raw_parity)
        except ValueError:
            errors.append(f"{file_name}: invalid parity: {raw_parity!r}")
            continue
        if parity < 0 or parity > 100:
            errors.append(f"{file_name}: parity must be 0..100, got {raw_parity!r}")
            continue
        parity_by_file[file_name] = parity

    missing = [name for name in required_files if name not in parity_by_file]
    if missing:
        errors.append(f"{summary}: missing required benchmark rows: {', '.join(missing)}")
    for name in required_files:
        if name in parity_by_file and parity_by_file[name] < min_parity:
            errors.append(f"{summary}: {name} parity {parity_by_file[name]:.2f}% < {min_parity:g}%")

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print(
        "verified benchmark summary: "
        f"{' '.join(required_files)} parity >= {min_parity:g}%"
    )
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", nargs="?", type=Path, default=DEFAULT_SUMMARY)
    parser.add_argument(
        "--required-files",
        default=DEFAULT_CORE_FILES,
        type=parse_required_files,
        help=f"space-separated required corpus basenames (default: {DEFAULT_CORE_FILES!r})",
    )
    parser.add_argument(
        "--min-parity",
        default=100.0,
        type=parse_min_parity,
        help="minimum parity required for required files (default: 100)",
    )
    parser.add_argument(
        "--require",
        action="store_true",
        help="fail if the summary file is absent",
    )
    args = parser.parse_args(argv)
    return validate(args.summary, args.required_files, args.min_parity, args.require)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
