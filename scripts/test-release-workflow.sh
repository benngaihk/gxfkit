#!/usr/bin/env bash
# Regression checks for the GitHub Release workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

workflow=".github/workflows/release.yml"
test -f "$workflow"

grep -F "name: Release" "$workflow" >/dev/null
grep -F "tags:" "$workflow" >/dev/null
grep -F '"v*"' "$workflow" >/dev/null
grep -F "workflow_dispatch:" "$workflow" >/dev/null
grep -F "for example v0.0.2" "$workflow" >/dev/null
grep -F "contents: write" "$workflow" >/dev/null
grep -F "group: release-\${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}" "$workflow" >/dev/null
grep -F "cancel-in-progress: false" "$workflow" >/dev/null
grep -F "Verify release tag matches crate version" "$workflow" >/dev/null
grep -F "Release tag must exist as a git tag" "$workflow" >/dev/null
grep -F 'git rev-parse -q --verify "refs/tags/${RELEASE_TAG}^{commit}"' "$workflow" >/dev/null
grep -F "Release checkout HEAD must match" "$workflow" >/dev/null
grep -F "python3 scripts/check-version-consistency.py" "$workflow" >/dev/null
grep -F -- "--scope cargo" "$workflow" >/dev/null
grep -F -- "--expected-version" "$workflow" >/dev/null
grep -F "Smoke test release binary" "$workflow" >/dev/null
grep -F "gxfkit unexpectedly overwrote smoke.gtf" "$workflow" >/dev/null
grep -F "grep 'refusing to overwrite' overwrite.err" "$workflow" >/dev/null
grep -F "Verify packaged archive" "$workflow" >/dev/null
grep -F "bash scripts/verify-release-archive.sh" "$workflow" >/dev/null
grep -F 'VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION="${RELEASE_TAG#v}"' "$workflow" >/dev/null
grep -F "Verify downloaded archives" "$workflow" >/dev/null
grep -F 'python3 scripts/check-release-dist.py --tag "$RELEASE_TAG" --dist dist' "$workflow" >/dev/null
grep -F 'VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION="${RELEASE_TAG#v}"' "$workflow" >/dev/null
grep -F "Verify tag readiness" "$workflow" >/dev/null
grep -F "git fetch --tags --force" "$workflow" >/dev/null
grep -F "python3 scripts/release-readiness.py" "$workflow" >/dev/null
grep -F -- "--phase tag" "$workflow" >/dev/null
grep -F "Verify release notes" "$workflow" >/dev/null
grep -F 'python3 scripts/check-release-notes.py --expected-version "${RELEASE_TAG#v}"' "$workflow" >/dev/null
grep -F 'test -f "docs/releases/${RELEASE_TAG}.md"' "$workflow" >/dev/null
grep -F "Generate release evidence" "$workflow" >/dev/null
grep -F "RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh > release-check.log 2>&1" "$workflow" >/dev/null
grep -F "printf 'release-check-exit-code=%s\\n' \"\$rc\" >> release-check.log" "$workflow" >/dev/null
grep -F 'VERSION="${RELEASE_TAG#v}" RELEASE_TAG="$RELEASE_TAG"' "$workflow" >/dev/null
grep -F "scripts/release-evidence.sh --release-check-log release-check.log > release-evidence.md" "$workflow" >/dev/null
grep -F "tail -180 release-check.log" "$workflow" >/dev/null
grep -F "VERIFY_RELEASE_ARCHIVE_SMOKE: \"0\"" "$workflow" >/dev/null
grep -F "draft: true" "$workflow" >/dev/null
grep -F "body_path: docs/releases/\${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}.md" "$workflow" >/dev/null
grep -F "fail_on_unmatched_files: true" "$workflow" >/dev/null
grep -F "name: release-evidence" "$workflow" >/dev/null
grep -F "path: release-evidence.md" "$workflow" >/dev/null

python3 - <<'PY'
from pathlib import Path
import yaml

path = Path(".github/workflows/release.yml")
data = yaml.safe_load(path.read_text(encoding="utf-8"))
assert data["permissions"]["contents"] == "write"
assert data["concurrency"]["group"] == (
    "release-${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}"
)
assert data["concurrency"]["cancel-in-progress"] is False
matrix = data["jobs"]["build"]["strategy"]["matrix"]["include"]
assert data["jobs"]["build"]["timeout-minutes"] == 45
assert data["jobs"]["publish"]["timeout-minutes"] == 20
packages = {item["package"] for item in matrix}
assert packages == {
    "linux-x86_64-static",
    "linux-aarch64-static",
    "macos-x86_64",
    "macos-aarch64",
}
build_runs = [
    step.get("run", "")
    for step in data["jobs"]["build"]["steps"]
    if isinstance(step, dict)
]
tag_guard_run = next(run for run in build_runs if "Release tag must start with v" in run)
assert "git fetch --tags --force" in tag_guard_run
assert 'git rev-parse -q --verify "refs/tags/${RELEASE_TAG}^{commit}"' in tag_guard_run
assert "Release tag must exist as a git tag" in tag_guard_run
assert "Release checkout HEAD must match" in tag_guard_run
assert "--scope cargo" in tag_guard_run and "--expected-version" in tag_guard_run
assert any("gxfkit unexpectedly overwrote smoke.gtf" in run for run in build_runs)
assert any("verify-release-archive.sh" in run for run in build_runs)
assert any("VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION" in run for run in build_runs)
publish_runs = [
    step.get("run", "")
    for step in data["jobs"]["publish"]["steps"]
    if isinstance(step, dict)
]
publish_names = [
    step.get("name", "")
    for step in data["jobs"]["publish"]["steps"]
    if isinstance(step, dict)
]
publish_steps = data["jobs"]["publish"]["steps"]
assert publish_steps[0]["uses"] == "actions/checkout@v7"
assert publish_steps[0]["with"]["ref"] == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref }}"
assert any(
    isinstance(step, dict)
    and step.get("uses") == "dtolnay/rust-toolchain@stable"
    and step.get("with", {}).get("components") == "clippy, rustfmt"
    for step in publish_steps
)
assert any(
    isinstance(step, dict) and step.get("uses") == "Swatinem/rust-cache@v2"
    for step in publish_steps
)
assert "Verify tag readiness" in publish_names
assert any(
    "release-readiness.py" in run
    and "--phase tag" in run
    and '--version "${RELEASE_TAG#v}"' in run
    and "git fetch --tags --force" in run
    for run in publish_runs
)
assert any("verify-release-archive.sh" in run for run in publish_runs)
assert any("check-release-dist.py" in run and '--tag "$RELEASE_TAG" --dist dist' in run for run in publish_runs)
assert any("VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION" in run for run in publish_runs)
assert any("check-release-notes.py" in run for run in publish_runs)
assert any("docs/releases/${RELEASE_TAG}.md" in run for run in publish_runs)
assert any(
    "release-evidence.sh --release-check-log release-check.log > release-evidence.md" in run
    and 'VERSION="${RELEASE_TAG#v}" RELEASE_TAG="$RELEASE_TAG"' in run
    and "RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh > release-check.log 2>&1" in run
    and "release-check-exit-code" in run
    and "tail -180 release-check.log" in run
    for run in publish_runs
)
release_steps = [
    step
    for step in data["jobs"]["publish"]["steps"]
    if isinstance(step, dict) and step.get("uses", "").startswith("softprops/action-gh-release")
]
assert len(release_steps) == 1
assert release_steps[0]["with"]["draft"] is True
assert release_steps[0]["with"]["body_path"] == (
    "docs/releases/${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}.md"
)
assert release_steps[0]["with"]["fail_on_unmatched_files"] is True
evidence_uploads = [
    step
    for step in data["jobs"]["publish"]["steps"]
    if isinstance(step, dict)
    and step.get("uses", "").startswith("actions/upload-artifact")
    and step.get("with", {}).get("name") == "release-evidence"
]
assert len(evidence_uploads) == 1
assert evidence_uploads[0]["if"] == "always()"
assert evidence_uploads[0]["with"]["path"] == "release-evidence.md"
PY

echo "verified release workflow"
