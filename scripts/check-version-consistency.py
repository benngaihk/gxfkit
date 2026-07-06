#!/usr/bin/env python3
"""Check release-facing version metadata stays in sync."""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def capture(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing {label}")
    return match.group(1)


def workspace_version() -> str:
    return capture(r'(?m)^version = "([^"]+)"$', read("Cargo.toml"), "workspace version")


def core_dependency_version() -> str:
    return capture(
        r'(?m)^gxfkit-core = \{ version = "([^"]+)", path = "\.\./gxfkit-core" \}$',
        read("crates/gxfkit/Cargo.toml"),
        "gxfkit-core dependency version",
    )


def bioconda_version(path: str) -> str:
    return capture(r'\{% set version = "([^"]+)" %\}', read(path), f"{path} version")


def bioconda_sha256(path: str) -> str:
    return capture(r"(?m)^  sha256: ([0-9a-f]{64})$", read(path), f"{path} sha256")


def check_equal(label: str, values: dict[str, str]) -> bool:
    unique = set(values.values())
    if len(unique) == 1:
        print(f"OK {label}: {next(iter(unique))}")
        return True
    print(f"ERROR {label} mismatch:", file=sys.stderr)
    for source, value in values.items():
        print(f"  {source}: {value}", file=sys.stderr)
    return False


def remote_sha256(url: str) -> str:
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()
    except (OSError, urllib.error.URLError) as exc:
        print(f"warning: Python download failed for {url}: {exc}", file=sys.stderr)

    try:
        curl = subprocess.Popen(
            ["curl", "-fsSL", url],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Python download failed and curl is not installed") from exc
    assert curl.stdout is not None
    while True:
        chunk = curl.stdout.read(1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    _, stderr = curl.communicate()
    if curl.returncode != 0:
        raise RuntimeError(
            f"Python download failed and curl exited {curl.returncode}: "
            f"{stderr.decode(errors='replace').strip()}"
        )
    return digest.hexdigest()


def parse_args(argv: list[str]) -> tuple[str | None, bool, str]:
    expected_version = None
    check_remote = False
    scope = "all"
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--check-remote-bioconda-sha256":
            check_remote = True
        elif arg == "--expected-version":
            i += 1
            if i >= len(argv):
                raise ValueError("--expected-version requires a value")
            expected_version = argv[i]
        elif arg == "--scope":
            i += 1
            if i >= len(argv):
                raise ValueError("--scope requires a value")
            scope = argv[i]
            if scope not in ("all", "cargo", "bioconda"):
                raise ValueError("--scope must be one of: all, cargo, bioconda")
        else:
            raise ValueError(f"unexpected argument: {arg}")
        i += 1
    if check_remote and scope == "cargo":
        raise ValueError("--check-remote-bioconda-sha256 requires --scope all or --scope bioconda")
    return expected_version, check_remote, scope


def main() -> int:
    try:
        expected_version, check_remote, scope = parse_args(sys.argv[1:])
    except ValueError as exc:
        print(
            f"usage: {Path(sys.argv[0]).name} "
            "[--expected-version X.Y.Z] [--scope all|cargo|bioconda] "
            "[--check-remote-bioconda-sha256]",
            file=sys.stderr,
        )
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    version = workspace_version()
    ok = True
    if expected_version is not None and scope in ("all", "cargo"):
        ok &= check_equal(
            "expected release version",
            {
                "expected": expected_version,
                "Cargo.toml workspace": version,
            },
        )
    if expected_version is not None and scope == "bioconda":
        ok &= check_equal(
            "expected Bioconda version",
            {
                "expected": expected_version,
                "packaging/bioconda/recipe/meta.yaml": bioconda_version(
                    "packaging/bioconda/recipe/meta.yaml"
                ),
                "packaging/bioconda/meta.yaml.template": bioconda_version(
                    "packaging/bioconda/meta.yaml.template"
                ),
            },
        )
    if scope in ("all", "cargo"):
        ok &= check_equal(
            "crate versions",
            {
                "Cargo.toml workspace": version,
                "crates/gxfkit dependency": core_dependency_version(),
            },
        )
    if scope in ("all", "bioconda"):
        bioconda_values = {
            "packaging/bioconda/recipe/meta.yaml": bioconda_version(
                "packaging/bioconda/recipe/meta.yaml"
            ),
            "packaging/bioconda/meta.yaml.template": bioconda_version(
                "packaging/bioconda/meta.yaml.template"
            ),
        }
        if scope == "all":
            bioconda_values = {"Cargo.toml workspace": version, **bioconda_values}
        ok &= check_equal("Bioconda versions", bioconda_values)
        ok &= check_equal(
            "Bioconda sha256 values",
            {
                "packaging/bioconda/recipe/meta.yaml": bioconda_sha256(
                    "packaging/bioconda/recipe/meta.yaml"
                ),
                "packaging/bioconda/meta.yaml.template": bioconda_sha256(
                    "packaging/bioconda/meta.yaml.template"
                ),
            },
        )

    if check_remote:
        expected = bioconda_sha256("packaging/bioconda/recipe/meta.yaml")
        source_version = bioconda_version("packaging/bioconda/recipe/meta.yaml")
        url = f"https://github.com/benngaihk/gxfkit/archive/refs/tags/v{source_version}.tar.gz"
        try:
            actual = remote_sha256(url)
        except RuntimeError as exc:
            print(f"ERROR remote sha256 check failed: {exc}", file=sys.stderr)
            return 1
        ok &= check_equal("Bioconda remote source sha256", {"recipe": expected, url: actual})

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
