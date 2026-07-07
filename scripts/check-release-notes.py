#!/usr/bin/env python3
"""Check the current workspace version has release notes with required evidence hooks."""
from __future__ import annotations

import os
import re
import sys
import argparse
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()


def workspace_version() -> str:
    text = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
    match = re.search(r'(?m)^version = "([^"]+)"$', text)
    if not match:
        raise RuntimeError("missing workspace version")
    return match.group(1)


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"release notes must mention: {needle}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-version", help="release version to check; defaults to workspace version")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    source_version = workspace_version()
    version = args.expected_version or source_version
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version):
        print(f"ERROR invalid expected version: {version}", file=sys.stderr)
        return 2
    tag = f"v{version}"
    path = ROOT / "docs" / "releases" / f"{tag}.md"
    if not path.is_file():
        print(f"ERROR missing release notes: {path.relative_to(ROOT)}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    if source_version != version:
        errors.append(
            f"workspace version {source_version} does not match expected release version {version}"
        )
    require(text, f"# gxfkit {tag} Release Notes", errors)
    require(text, "Status:", errors)
    require(text, "public GitHub Release", errors)
    require(text, "public GitHub Release, Bioconda, and Crates.io package", errors)
    require(text, "Full public readiness passed", errors)
    require(text, "public readiness is tracked by", errors)
    require(text, "AGAT 1.7.0", errors)
    require(text, "100.00% normalized parity", errors)
    for corpus in ("human_chr1", "human_chr21", "yeast"):
        require(text, corpus, errors)
    require(text, "no-overwrite", errors)
    require(text, "deterministic local", errors)
    require(text, "`release-check.sh` contract guard", errors)
    require(text, "Install Now", errors)
    require(text, f"conda install -c conda-forge -c bioconda gxfkit={version}", errors)
    require(text, f"cargo install gxfkit --version {version}", errors)
    require(text, "printf 'release-check-exit-code=%s\\n' \"$rc\" >> release-check.log", errors)
    require(text, "release-check-exit-code", errors)
    require(text, "python3 scripts/check-release-check.py", errors)
    require(text, "scripts/release-evidence.sh --allow-dirty --release-check-log release-check.log > release-evidence.md", errors)
    require(text, 'exit "$rc"', errors)
    require(text, f"python3 scripts/github-source-sha256.py {version} --format prepare-command", errors)
    require(text, "python3 scripts/release-readiness.py --phase public --check-public --run-public-audit", errors)
    require(text, f"VERSION={version} RELEASE_TAG={tag} bash scripts/verify-public-installs.sh", errors)
    require(text, 'VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates"', errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0", errors)
    require(
        text,
        'VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \\ '
        'VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \\ '
        'VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \\ '
        'BENCH_FILES="human_chr1 human_chr21 yeast" \\ '
        f"VERSION={version} RELEASE_TAG={tag} bash scripts/verify-public-installs.sh",
        errors,
    )
    require(text, "A staged public install audit allowing only the missing Crates.io channel passed", errors)
    require(text, "on 2026-07-07", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1", errors)
    require(
        text,
        "public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[crates ] failed=[]",
        errors,
    )
    require(
        text,
        "public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]",
        errors,
    )
    require(text, "scripts/release-evidence.sh --check-public > release-evidence.md", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100", errors)
    require(text, 'BENCH_FILES="human_chr1 human_chr21 yeast"', errors)
    require(text, "Known Limits", errors)
    require(text, "Public `v0.0.1` packages predate the no-overwrite guard", errors)
    require(text, "Drosophila", errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print(f"verified release notes for {tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
