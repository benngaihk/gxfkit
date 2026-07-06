#!/usr/bin/env python3
"""Validate the downloaded release dist directory before creating a draft release."""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TAG_RE = re.compile(r"^v[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$")


def release_packages(readiness_path: Path) -> tuple[str, ...]:
    module = ast.parse(readiness_path.read_text(encoding="utf-8"))
    for node in module.body:
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == "RELEASE_PACKAGES" for target in node.targets):
            continue
        value = ast.literal_eval(node.value)
        if not isinstance(value, (tuple, list)):
            raise SystemExit("release-readiness RELEASE_PACKAGES must be a tuple or list")
        packages = tuple(value)
        if not packages:
            raise SystemExit("release-readiness RELEASE_PACKAGES must not be empty")
        if any(not isinstance(package, str) for package in packages):
            raise SystemExit("release-readiness RELEASE_PACKAGES entries must be strings")
        if len(set(packages)) != len(packages):
            raise SystemExit("release-readiness RELEASE_PACKAGES must not contain duplicates")
        return packages
    raise SystemExit("release-readiness.py does not define RELEASE_PACKAGES")


def expected_assets(tag: str, packages: tuple[str, ...]) -> set[str]:
    assets: set[str] = set()
    for package in packages:
        archive = f"gxfkit-{tag}-{package}.tar.gz"
        assets.add(archive)
        assets.add(f"{archive}.sha256")
    return assets


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, help="release tag, for example v0.0.2")
    parser.add_argument(
        "--dist",
        type=Path,
        default=ROOT / "dist",
        help="directory containing downloaded release artifacts",
    )
    parser.add_argument(
        "--readiness",
        type=Path,
        default=ROOT / "scripts" / "release-readiness.py",
        help="release-readiness.py path used as the package-list source",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not TAG_RE.fullmatch(args.tag):
        print(f"ERROR --tag must look like vX.Y.Z, got: {args.tag}", file=sys.stderr)
        return 2
    if not args.dist.is_dir():
        print(f"ERROR dist directory not found: {args.dist}", file=sys.stderr)
        return 1

    packages = release_packages(args.readiness)
    expected = expected_assets(args.tag, packages)
    actual = {path.name for path in args.dist.iterdir() if path.is_file()}
    package_like = {
        name
        for name in actual
        if name.startswith(f"gxfkit-{args.tag}-")
        and (name.endswith(".tar.gz") or name.endswith(".tar.gz.sha256"))
    }

    missing = sorted(expected - actual)
    unexpected = sorted(package_like - expected)
    errors: list[str] = []
    if missing:
        errors.append("missing release artifact(s): " + ", ".join(missing))
    if unexpected:
        errors.append("unexpected release package artifact(s): " + ", ".join(unexpected))

    for name in sorted(expected):
        path = args.dist / name
        if path.is_file() and path.stat().st_size == 0:
            errors.append(f"release artifact is empty: {name}")

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print(
        "verified release dist artifact set: "
        f"{len(packages)} package(s), {len(expected)} artifact(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
