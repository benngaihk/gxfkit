#!/usr/bin/env python3
"""Check docs/RELEASE.md stays aligned with release automation."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
DOC = ROOT / "docs" / "RELEASE.md"


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"docs/RELEASE.md must mention: {needle}")


def forbid(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) in compact(text):
        errors.append(f"docs/RELEASE.md must not mention: {needle}")


def require_balanced_fences(text: str, errors: list[str]) -> None:
    fence_count = sum(1 for line in text.splitlines() if line.startswith("```"))
    if fence_count % 2 != 0:
        errors.append("docs/RELEASE.md must have balanced fenced code blocks")


def main() -> int:
    text = DOC.read_text(encoding="utf-8")
    errors: list[str] = []
    require_balanced_fences(text, errors)

    for heading in (
        "# Release Checklist",
        "## 1. Preflight",
        "## 2. Crates.io",
        "## 3. GitHub Release",
        "## 4. Bioconda",
        "## 5. Announcement",
    ):
        require(text, heading, errors)

    for snippet in (
        "bash scripts/release-check.sh",
        "printf 'release-check-exit-code=%s\\n' \"$rc\" >> release-check.log",
        "release-check-exit-code=0",
        "scripts/release-evidence.sh --allow-dirty --release-check-log release-check.log > release-evidence.md",
        'exit "$rc"',
        "--release-check-log",
        "failed preflight runs still leave pasteable diagnostics",
        "using an offline install smoke inside `release-check.sh`",
        "checks the release artifact contract so the workflow matrix,",
        "readiness asset list, archive names, and upload globs stay aligned",
        "python3 scripts/prepare-next-version.py X.Y.Z --cargo-only",
        "RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh",
        "python3 scripts/release-readiness.py --phase tag",
        "python3 scripts/github-source-sha256.py X.Y.Z --format prepare-command",
        "python3 scripts/prepare-next-version.py X.Y.Z",
        "--bioconda-sha256 <sha256-of-vX.Y.Z-source-archive>",
        "requires the Bioconda sha256 and a local `vX.Y.Z` git tag",
        "source archive that does not exist yet",
        "workflow policy, crates.io metadata, release status, install-doc,",
        "validates `benchmark/results/summary.tsv` when present",
        "python3 scripts/check-benchmark-summary.py --require",
        "checks that `docs/PARITY.md` still matches the release gate",
        "checks that `release-check.sh` keeps its deterministic local preflight contract",
        "includes the release-check contract guard in the release evidence report",
        "includes an `Evidence Status` section",
        "not by itself proof that the release is closed",
        "uses `scripts/check-package-files.sh` to confirm both crate archives",
        "`Cargo.toml`, `README.md`, `LICENSE`, and the crate source",
        "the crate source entrypoint (`src/lib.rs` for `gxfkit-core`, `src/main.rs` for `gxfkit`)",
        "cargo package\n--locked",
        "Local `release-check.sh` runs its final `cargo package` smoke in offline mode",
        "RELEASE_CHECK_PACKAGE_NETWORK=1",
        "PACKAGE_FILES_ALLOW_DIRTY=0",
        "release.yml` may use `contents: write`",
        "CI, Crates.io publish, and public-install audit workflows must stay at",
        "`contents: read`",
        "manual **Publish Crates.io** GitHub Actions workflow",
        "package-file-list, residual-writer, and version-consistency regressions",
        "`gxfkit-core`-only workflow run waits for `gxfkit-core` registry",
        "scripts/release-readiness.py --phase tag --version X.Y.Z",
        "uploads a `release-evidence.md` artifact from the clean tag checkout",
        "runs `RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh` from the clean",
        "appends `release-check-exit-code`",
        "`scripts/release-evidence.sh --release-check-log`",
        "stops before creating the draft if the preflight failed",
        "source_ref",
        "requested version looks like `X.Y.Z`",
        "`source_ref` is non-empty and contains no whitespace",
        "`confirm` is exactly `publish`",
        "CARGO_REGISTRY_TOKEN",
        "verifies that the secret is configured before the expensive publish preflight starts",
        "cargo publish -p gxfkit-core --registry crates-io",
        "cargo publish -p gxfkit --registry crates-io",
        "VERSION=X.Y.Z bash scripts/verify-crates-install.sh",
        "python3 scripts/release-readiness.py --phase public --check-public",
        "python3 scripts/release-readiness.py --phase public --check-public --run-public-audit",
        "VERSION=X.Y.Z RELEASE_TAG=vX.Y.Z bash scripts/verify-public-installs.sh",
        "non-draft, non-prerelease release",
        "remote GitHub tag resolves to the local tag commit",
        "all four platform archives plus",
        "uploaded, non-empty, and have the expected GitHub download URLs",
        "The expected package asset set is closed",
        "duplicate asset names fail readiness",
        "extra `gxfkit-vX.Y.Z-*.tar.gz` or `gxfkit-vX.Y.Z-*.tar.gz.sha256` assets fail",
        "unless the release matrix and readiness package list are updated together",
        "Ordinary non-package release notes attachments are allowed",
        "contain one checksum line that points at the matching archive name",
        "four checksum digests must be unique",
        "Bioconda `linux-64` and `osx-64` build `0` main package files",
        "without the `broken` label",
        "Crates.io versions to be present, explicitly `yanked: false`",
        "valid checksum plus non-zero crate size",
        "Public channel discovery uses bounded retries and timeouts",
        "`--run-public-audit` readiness mode runs the same strict audit",
        "validates the recorded log with `scripts/check-public-audit-log.py`",
        "manual **Public Install Audit** GitHub Actions workflow",
        "validates the requested `version`/`tag` pair before checkout",
        "malformed versions or mismatched tags fail before any public install work starts",
        "the always-running log-validation step enforces the final",
        "the workflow validates the recorded log against those requested staged inputs",
        "`Recorded Public Audit Log Guards` block",
        "`Final Strict Public Audit Log Guards` block still fails",
        "records and validates the Crates.io install verifier path",
        "`scripts/verify-crates-install.sh`",
        "repository-relative `scripts/*.sh` path",
        "absolute paths, path traversal, shell options, and paths with whitespace are rejected",
        'VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates"',
        "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1",
        "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0",
        "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1",
        "VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100",
        "git tag -a vX.Y.Z",
        "git push origin vX.Y.Z",
        "checking that `vX.Y.Z` exists as a git tag",
        "checkout `HEAD` matches that tag",
        "RELEASE_TAG=vX.Y.Z bash scripts/verify-github-release-install.sh",
        "This verifier checks the no-overwrite guard by default",
        "VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0",
        "legacy packages that predate the no-overwrite guard",
        "checksum, archive-safety, version, and conversion smoke checks",
        "RELEASE_TAG=vX.Y.Z bash scripts/verify-github-release-linux-docker.sh",
        "downloaded artifact set contains exactly the expected",
        "four platform archives plus matching `.sha256` files",
        "This clean-container verifier also runs `scripts/verify-release-archive.sh`",
        "VERIFY_RELEASE_ARCHIVE_SMOKE=0",
        "RELEASE_TAG=vX.Y.Z BENCH_FILES=yeast bash scripts/verify-github-release-parity.sh",
        "PACKAGE=linux-x86_64-static VERIFY_RELEASE_ARCHIVE_SMOKE=0",
        "python3 scripts/check-version-consistency.py --check-remote-bioconda-sha256",
        "VERSION=X.Y.Z bash scripts/verify-bioconda-install.sh",
        "This verifier checks the no-overwrite guard by default",
        "VERIFY_BIOCONDA_NO_OVERWRITE=0",
        "bioconda-recipes#66815",
        "AGAT baseline version",
    ):
        require(text, snippet, errors)

    forbid(text, "MIN_PARITY=98", errors)
    forbid(text, "for example 0.0.1", errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("verified release guide")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
