#!/usr/bin/env python3
"""Check docs/RELEASE-STATUS.md records version/tag release constraints."""
from __future__ import annotations

import re
import subprocess
import sys
import os
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
DOC = ROOT / "docs" / "RELEASE-STATUS.md"


def run_git(*args: str) -> str | None:
    proc = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def workspace_version() -> str:
    text = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
    match = re.search(r'(?m)^version = "([^"]+)"$', text)
    if not match:
        raise RuntimeError("missing workspace version")
    return match.group(1)


def status_version(text: str, label: str) -> str:
    match = re.search(rf"(?m)^## {re.escape(label)}: `([^`]+)`$", text)
    if not match:
        raise RuntimeError(f"docs/RELEASE-STATUS.md is missing {label}")
    return match.group(1)


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"docs/RELEASE-STATUS.md must mention: {needle}")


def forbid(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) in compact(text):
        errors.append(f"docs/RELEASE-STATUS.md must not mention: {needle}")


def main() -> int:
    version = workspace_version()
    tag = f"v{version}"
    text = DOC.read_text(encoding="utf-8")
    github_version = status_version(text, "Current public GitHub Release")
    bioconda_version = status_version(text, "Current public Bioconda")
    crates_version = status_version(text, "Current public Crates.io")
    cargo_candidate_version = status_version(text, "Current Cargo release candidate")
    errors: list[str] = []

    forbid(text, "default public install smoke", errors)
    require(text, "basic version/conversion smoke", errors)
    require(text, "strict no-overwrite audit", errors)
    require(text, f"GitHub Release `{tag}` exists, is public, and is not a prerelease", errors)
    require(text, "expected eight assets", errors)
    require(
        text,
        f"RELEASE_TAG={tag} bash scripts/verify-github-release-install.sh",
        errors,
    )
    require(
        text,
        f"RELEASE_TAG={tag} bash scripts/verify-github-release-linux-docker.sh",
        errors,
    )
    require(
        text,
        f'RELEASE_TAG={tag} BENCH_FILES="human_chr1 human_chr21 yeast" bash scripts/verify-github-release-parity.sh',
        errors,
    )
    require(text, "re-verified from a clean micromamba container", errors)
    require(text, "bioconda-recipes#66815", errors)
    require(text, "is merged", errors)
    require(text, "public Bioconda package state", errors)
    require(
        text,
        "VERSION=0.0.1 VERIFY_BIOCONDA_NO_OVERWRITE=0 bash scripts/verify-bioconda-install.sh",
        errors,
    )
    require(text, f"Anaconda package metadata lists Bioconda `gxfkit {version}` files", errors)
    require(text, "linux-64", errors)
    require(text, "osx-64", errors)
    require(text, f"Bioconda `gxfkit {version}` passed clean Linux install verification", errors)
    require(text, "smoke conversion", errors)
    require(text, "no-overwrite verification", errors)
    require(text, f"VERSION={version} bash scripts/verify-bioconda-install.sh", errors)
    require(text, f"Crates.io `gxfkit-core {version}` is published and visible", errors)
    require(text, f"Crates.io `gxfkit {version}` is published and visible", errors)
    require(text, f"Crates.io `gxfkit {version}` passed clean install verification", errors)
    require(text, f"VERSION={version} bash scripts/verify-crates-install.sh", errors)

    if github_version != version:
        errors.append(f"Current public GitHub Release {github_version} != workspace version {version}")
    if cargo_candidate_version != version:
        errors.append(f"Current Cargo release candidate {cargo_candidate_version} != workspace version {version}")
    if bioconda_version != version:
        errors.append(f"Current public Bioconda {bioconda_version} != workspace version {version}")
    if crates_version != version:
        errors.append(f"Current public Crates.io {crates_version} != workspace version {version}")

    stale_workspace_claim = re.search(
        r"current working tree still reports workspace version `([^`]+)`",
        text,
        re.IGNORECASE,
    )
    if stale_workspace_claim and stale_workspace_claim.group(1) != version:
        errors.append(
            "docs/RELEASE-STATUS.md has a stale current-working-tree version "
            f"claim: {stale_workspace_claim.group(1)} != {version}"
        )

    tag_commit = run_git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}")
    head = run_git("rev-parse", "HEAD")
    if tag_commit and head and tag_commit != head:
        require(text, f"existing `{tag}` tag points at an older commit", errors)
        require(text, f"Crates.io `{version}` was published from the existing `{tag}` tag", errors)
        require(text, f"The existing `{tag}` tag points at the release-candidate commit. It must not be moved.", errors)
        require(text, "the next public release must bump the workspace version", errors)
    require(text, f"Current public Bioconda: `{version}`", errors)
    require(text, f"Current Cargo release candidate: `{version}`", errors)
    require(text, "offline install/package smoke checks", errors)
    require(text, "python3 scripts/check-release-check.py", errors)
    require(text, "deterministic local preflight contract", errors)
    require(text, f"Remaining `{version}` public closure", errors)
    require(text, "None. GitHub Release, Bioconda, Crates.io, and the strict public audit are all complete", errors)
    require(text, "python3 scripts/release-readiness.py --phase public --check-public --run-public-audit", errors)
    require(text, "release-readiness --run-public-audit", errors)
    require(text, 'VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates"', errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100", errors)
    require(text, "A staged public install audit allowing only the missing Crates.io channel passed", errors)
    require(text, "on 2026-07-07", errors)
    require(text, "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1", errors)
    require(text, "BENCH_FILES=\"human_chr1 human_chr21 yeast\"", errors)
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

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print("verified release status doc")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
