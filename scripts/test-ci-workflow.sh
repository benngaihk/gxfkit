#!/usr/bin/env bash
# Regression checks for the main CI workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

workflow=".github/workflows/ci.yml"
test -f "$workflow"

grep -F "name: CI" "$workflow" >/dev/null
grep -F "python3 scripts/check-version-consistency.py --scope cargo" "$workflow" >/dev/null
grep -F "python3 scripts/check-version-consistency.py --scope bioconda" "$workflow" >/dev/null
grep -F "bash scripts/test-crate-metadata.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-crate-metadata.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-artifacts.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-artifacts.py" "$workflow" >/dev/null
grep -F "bash scripts/test-github-source-sha256.sh" "$workflow" >/dev/null
grep -F "MIN_PARITY=100 python benchmark/summarize.py benchmark/results tests/parity/normalize.py" "$workflow" >/dev/null
if grep -Fx "      - run: python3 scripts/check-version-consistency.py" "$workflow" >/dev/null; then
  echo "CI must not require full Cargo/Bioconda version sync during staged release prep" >&2
  exit 1
fi
grep -F "bash scripts/test-ci-workflow.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-publish-crates-workflow.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-workflow-policy.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-workflow-policy.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-readiness.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-release-evidence.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-local-cargo-install-verifier.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-release-notes.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-notes.py" "$workflow" >/dev/null
grep -F "bash scripts/test-install-docs.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-install-docs.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-doc.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-doc.py" "$workflow" >/dev/null
grep -F "bash scripts/test-maintainer-surfaces.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-maintainer-surfaces.py" "$workflow" >/dev/null
grep -F "bash scripts/test-shell-syntax.sh" "$workflow" >/dev/null
grep -F "python3 scripts/test-python-syntax.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-check.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-check.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-check-log.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-repo-hygiene.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-executable-scripts.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-public-audit-log.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-benchmark-summary.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-benchmark-summary.py --require" "$workflow" >/dev/null
grep -F "bash scripts/test-parity-doc.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-parity-doc.py" "$workflow" >/dev/null
grep -F "bash scripts/test-package-files.sh" "$workflow" >/dev/null
grep -F "PACKAGE_FILES_ALLOW_DIRTY=0 bash scripts/check-package-files.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-check-crates-publish-state.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-trigger-crates-publish.sh" "$workflow" >/dev/null

python3 - <<'PY'
from pathlib import Path
import yaml

path = Path(".github/workflows/ci.yml")
data = yaml.safe_load(path.read_text(encoding="utf-8"))
assert data["permissions"]["contents"] == "read"
assert data["jobs"]["build-test"]["runs-on"] == "ubuntu-latest"
assert data["jobs"]["build-test"]["timeout-minutes"] == 30
assert data["jobs"]["parity"]["timeout-minutes"] == 60
steps = data["jobs"]["build-test"]["steps"]
runs = [step.get("run", "") for step in steps if isinstance(step, dict)]
assert any("check-version-consistency.py --scope cargo" in run for run in runs)
assert any("check-version-consistency.py --scope bioconda" in run for run in runs)
assert any("test-crate-metadata.sh" in run for run in runs)
assert any("check-crate-metadata.py" in run for run in runs)
assert any("test-release-artifacts.sh" in run for run in runs)
assert any("check-release-artifacts.py" in run for run in runs)
assert any("test-github-source-sha256.sh" in run for run in runs)
assert not any(run == "python3 scripts/check-version-consistency.py" for run in runs)
parity_steps = data["jobs"]["parity"]["steps"]
parity_runs = [step.get("run", "") for step in parity_steps if isinstance(step, dict)]
assert any("MIN_PARITY=100 python benchmark/summarize.py" in run for run in parity_runs)
assert any("check-benchmark-summary.py --require" in run for run in parity_runs)
assert any("test-benchmark-summary.sh" in run for run in runs)
assert any("test-parity-doc.sh" in run for run in runs)
assert any("check-parity-doc.py" in run for run in runs)
assert any("test-package-files.sh" in run for run in runs)
assert any("PACKAGE_FILES_ALLOW_DIRTY=0 bash scripts/check-package-files.sh" in run for run in runs)
assert any("test-check-crates-publish-state.sh" in run for run in runs)
assert any("test-trigger-crates-publish.sh" in run for run in runs)
assert any("test-publish-crates-workflow.sh" in run for run in runs)
assert any("test-workflow-policy.sh" in run for run in runs)
assert any("check-workflow-policy.py" in run for run in runs)
assert any("test-release-readiness.sh" in run for run in runs)
assert any("test-release-evidence.sh" in run for run in runs)
assert any("test-local-cargo-install-verifier.sh" in run for run in runs)
assert any("test-release-notes.sh" in run for run in runs)
assert any("check-release-notes.py" in run for run in runs)
assert any("test-install-docs.sh" in run for run in runs)
assert any("check-install-docs.py" in run for run in runs)
assert any("test-release-doc.sh" in run for run in runs)
assert any("check-release-doc.py" in run for run in runs)
assert any("test-maintainer-surfaces.sh" in run for run in runs)
assert any("check-maintainer-surfaces.py" in run for run in runs)
assert any("test-shell-syntax.sh" in run for run in runs)
assert any("test-python-syntax.py" in run for run in runs)
assert any("test-release-check.sh" in run for run in runs)
assert any("check-release-check.py" in run for run in runs)
assert any("test-release-check-log.sh" in run for run in runs)
assert any("test-repo-hygiene.sh" in run for run in runs)
assert any("test-executable-scripts.sh" in run for run in runs)
assert any("test-public-audit-log.sh" in run for run in runs)
PY

echo "verified CI workflow"
