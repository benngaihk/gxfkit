#!/usr/bin/env python3
"""Check that release archive names and artifact paths stay verifier-compatible."""
from __future__ import annotations

import argparse
import ast
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PACKAGES = {
    "linux-x86_64-static",
    "linux-aarch64-static",
    "macos-x86_64",
    "macos-aarch64",
}


def read_text(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"missing file: {path}")
    return path.read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"{label} is missing: {needle}")


def require_line_count(text: str, line: str, expected: int, label: str) -> None:
    count = sum(1 for item in text.splitlines() if item.strip() == line)
    if count != expected:
        raise SystemExit(f"{label} must appear {expected} time(s), found {count}: {line}")


def workflow_release_packages(workflow: str) -> set[str]:
    packages = set(re.findall(r"^\s*package:\s*([A-Za-z0-9_.-]+)\s*$", workflow, re.MULTILINE))
    if not packages:
        raise SystemExit("release workflow does not define matrix package names")
    return packages


def readiness_release_packages(readiness: str) -> set[str]:
    module = ast.parse(readiness)
    for node in module.body:
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == "RELEASE_PACKAGES" for target in node.targets):
            continue
        value = ast.literal_eval(node.value)
        if not isinstance(value, (tuple, list)):
            raise SystemExit("release-readiness RELEASE_PACKAGES must be a tuple or list")
        packages = []
        for item in value:
            if not isinstance(item, str):
                raise SystemExit("release-readiness RELEASE_PACKAGES entries must be strings")
            packages.append(item)
        if len(packages) != len(set(packages)):
            raise SystemExit("release-readiness RELEASE_PACKAGES must not contain duplicates")
        if not packages:
            raise SystemExit("release-readiness RELEASE_PACKAGES must not be empty")
        return set(packages)
    raise SystemExit("release-readiness.py does not define RELEASE_PACKAGES")


def check_package_names(packages: set[str], label: str) -> None:
    if packages != EXPECTED_PACKAGES:
        expected = ", ".join(sorted(EXPECTED_PACKAGES))
        actual = ", ".join(sorted(packages))
        raise SystemExit(f"{label} packages differ from expected set: {actual}; expected: {expected}")
    for package in packages:
        if not re.fullmatch(r"[A-Za-z0-9._-]+", package):
            raise SystemExit(f"{label} package name has unsafe characters: {package}")
        sample = f"gxfkit-v1.2.3-{package}.tar.gz"
        if not re.fullmatch(r"gxfkit-v.*\.tar\.gz", sample):
            raise SystemExit(f"{label} package would not match verifier archive glob: {sample}")


def check_package_alignment(workflow_packages: set[str], readiness_packages: set[str]) -> None:
    if workflow_packages == readiness_packages:
        return
    workflow = ", ".join(sorted(workflow_packages))
    readiness = ", ".join(sorted(readiness_packages))
    raise SystemExit(
        "release workflow matrix packages and release-readiness packages differ: "
        f"workflow={workflow}; readiness={readiness}"
    )


def check_workflow(workflow: str) -> set[str]:
    packages = workflow_release_packages(workflow)
    check_package_names(packages, "release workflow")

    required = [
        ('name="gxfkit-${RELEASE_TAG}-${PACKAGE}"', "archive base name"),
        ('rm -rf "dist/${name}"', "clean archive staging directory"),
        ('tar -C dist -czf "dist/${name}.tar.gz" "${name}"', "archive creation"),
        ('shasum -a 256 "${name}.tar.gz" > "${name}.tar.gz.sha256"', "checksum creation"),
        ('bash scripts/verify-release-archive.sh "dist/gxfkit-${RELEASE_TAG}-${PACKAGE}.tar.gz"', "build archive verification"),
        ("merge-multiple: true", "artifact download"),
        ('python3 scripts/check-release-dist.py --tag "$RELEASE_TAG" --dist dist', "downloaded artifact set verification"),
        ("archives=(dist/*.tar.gz)", "publish archive discovery"),
        ('bash scripts/verify-release-archive.sh "$archive"', "publish archive verification"),
        ("VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION", "archive version verification"),
        ("fail_on_unmatched_files: true", "release file upload guard"),
    ]
    for needle, label in required:
        require(workflow, needle, label)
    require_line_count(workflow, "dist/*.tar.gz", 2, "artifact upload/release files")
    require_line_count(workflow, "dist/*.tar.gz.sha256", 2, "artifact upload/release checksums")
    return packages


def check_verifier(verifier: str) -> None:
    required = [
        ("gxfkit-v*.tar.gz) ;;", "archive name case glob"),
        ('archive_root="${archive_name%.tar.gz}"', "archive root derivation"),
        ('if [ "$checksum_target" != "$archive_name" ]; then', "checksum target guard"),
        ("lowercase sha256 digest", "lowercase checksum guard"),
        ("archive has duplicate member", "duplicate archive member guard"),
        ("archive member must not be a link", "archive link guard"),
        ('archive has unexpected member', "unexpected archive member guard"),
        ("VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE must be 0 or 1", "no-overwrite switch validation"),
        ('if [ "$verify_no_overwrite" = 1 ]; then', "conditional no-overwrite smoke"),
        ('tar -xzf "$archive" -C "$tmp"', "archive extraction"),
        ('grep \'refusing to overwrite\' "$tmp/overwrite.err" >/dev/null', "no-overwrite smoke"),
    ]
    for needle, label in required:
        require(verifier, needle, label)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--workflow",
        type=Path,
        default=ROOT / ".github/workflows/release.yml",
        help="release workflow to inspect",
    )
    parser.add_argument(
        "--verifier",
        type=Path,
        default=ROOT / "scripts/verify-release-archive.sh",
        help="release archive verifier to inspect",
    )
    parser.add_argument(
        "--readiness",
        type=Path,
        default=ROOT / "scripts/release-readiness.py",
        help="release readiness script to inspect",
    )
    args = parser.parse_args()

    workflow = read_text(args.workflow)
    verifier = read_text(args.verifier)
    readiness = read_text(args.readiness)
    workflow_packages = check_workflow(workflow)
    readiness_packages = readiness_release_packages(readiness)
    check_package_names(readiness_packages, "release-readiness")
    check_package_alignment(workflow_packages, readiness_packages)
    check_verifier(verifier)
    print("verified release artifact contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
