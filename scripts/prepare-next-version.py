#!/usr/bin/env python3
"""Prepare version metadata for the next public release.

Use --cargo-only before cutting the tag. After the tag exists and the GitHub
source archive sha256 is known, rerun with --bioconda-sha256 to update the
Bioconda recipe/template as well.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def replace_once(path: Path, pattern: str, replacement: str) -> bool:
    text = path.read_text(encoding="utf-8")
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"{path.relative_to(ROOT)}: expected exactly one match for {pattern}")
    if new != text:
        path.write_text(new, encoding="utf-8")
        return True
    return False


def git_worktree_root() -> Path | None:
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return Path(proc.stdout.strip()).resolve()


def git_tag_exists(version: str) -> bool:
    proc = subprocess.run(
        ["git", "rev-parse", "-q", "--verify", f"refs/tags/v{version}^{{commit}}"],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode == 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="new workspace version, for example 0.0.2")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--cargo-only",
        action="store_true",
        help="only update Cargo workspace and crate dependency versions",
    )
    mode.add_argument(
        "--bioconda-sha256",
        help="sha256 for https://github.com/benngaihk/gxfkit/archive/refs/tags/vVERSION.tar.gz",
    )
    args = parser.parse_args(argv)

    if not VERSION_RE.fullmatch(args.version):
        parser.error(f"invalid version: {args.version}")
    if args.bioconda_sha256 and not SHA256_RE.fullmatch(args.bioconda_sha256):
        parser.error("--bioconda-sha256 must be a lowercase 64-character sha256")
    if args.bioconda_sha256 and git_worktree_root() == ROOT and not git_tag_exists(args.version):
        parser.error(
            f"--bioconda-sha256 requires local git tag v{args.version}; "
            "cut or fetch the tag before updating Bioconda metadata"
        )

    changed: list[str] = []
    edits = [
        (
            ROOT / "Cargo.toml",
            r'^version = "[^"]+"$',
            f'version = "{args.version}"',
        ),
        (
            ROOT / "crates" / "gxfkit" / "Cargo.toml",
            r'^gxfkit-core = \{ version = "[^"]+", path = "\.\./gxfkit-core" \}$',
            f'gxfkit-core = {{ version = "{args.version}", path = "../gxfkit-core" }}',
        ),
    ]
    if args.bioconda_sha256:
        for recipe in (
            ROOT / "packaging" / "bioconda" / "recipe" / "meta.yaml",
            ROOT / "packaging" / "bioconda" / "meta.yaml.template",
        ):
            edits.extend(
                [
                    (
                        recipe,
                        r'^\{% set version = "[^"]+" %\}$',
                        f'{{% set version = "{args.version}" %}}',
                    ),
                    (
                        recipe,
                        r"^  sha256: [0-9a-f]{64}$",
                        f"  sha256: {args.bioconda_sha256}",
                    ),
                ]
            )

    for path, pattern, replacement in edits:
        if replace_once(path, pattern, replacement):
            rel = str(path.relative_to(ROOT))
            if rel not in changed:
                changed.append(rel)

    for rel in changed:
        print(f"updated {rel}")
    if not changed:
        print("version metadata already up to date")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
