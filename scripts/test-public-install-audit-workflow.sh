#!/usr/bin/env bash
# Regression checks for the manual Public Install Audit workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

workflow=".github/workflows/public-install-audit.yml"
test -f "$workflow"

grep -F "name: Public Install Audit" "$workflow" >/dev/null
grep -F "workflow_dispatch:" "$workflow" >/dev/null
grep -F "version:" "$workflow" >/dev/null
grep -F "tag:" "$workflow" >/dev/null
grep -F "channels:" "$workflow" >/dev/null
grep -F "allow_missing_crates:" "$workflow" >/dev/null
grep -F "verify_no_overwrite:" "$workflow" >/dev/null
grep -F "min_parity:" "$workflow" >/dev/null
grep -F "crates_install_script:" "$workflow" >/dev/null
grep -F "Repository-relative Crates.io install verifier script under scripts/*.sh" "$workflow" >/dev/null
grep -F "Validate workflow inputs" "$workflow" >/dev/null
grep -F "Version must look like X.Y.Z" "$workflow" >/dev/null
grep -F "Version and tag disagree" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALL_CHANNELS: \${{ inputs.channels }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES: \${{ inputs.allow_missing_crates && '1' || '0' }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE: \${{ inputs.verify_no_overwrite && '1' || '0' }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_MIN_PARITY: \${{ inputs.min_parity }}" "$workflow" >/dev/null
grep -F "BENCH_FILES: \${{ inputs.bench_files }}" "$workflow" >/dev/null
grep -F "VERIFY_CRATES_INSTALL_SCRIPT: \${{ inputs.crates_install_script }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 bash scripts/verify-public-installs.sh >/dev/null" "$workflow" >/dev/null
grep -F 'default: "github-linux github-parity bioconda crates"' "$workflow" >/dev/null
grep -F 'default: "human_chr1 human_chr21 yeast"' "$workflow" >/dev/null
grep -F 'default: "100"' "$workflow" >/dev/null
grep -F 'default: "scripts/verify-crates-install.sh"' "$workflow" >/dev/null
grep -F "bash scripts/verify-public-installs.sh 2>&1 | tee public-audit.log" "$workflow" >/dev/null
grep -F "audit_rc=\${PIPESTATUS[0]}" "$workflow" >/dev/null
grep -F 'echo "public-audit-exit-code=${audit_rc}" | tee -a public-audit.log' "$workflow" >/dev/null
grep -F "Audit exit code is recorded; the log validation step enforces final status." "$workflow" >/dev/null
if grep -F 'exit "$audit_rc"' "$workflow" >/dev/null; then
  echo "public audit step must not exit before log validation can run" >&2
  exit 1
fi
grep -F "Validate public audit log" "$workflow" >/dev/null
grep -F "if: always()" "$workflow" >/dev/null
grep -F "VERSION: \${{ inputs.version }}" "$workflow" >/dev/null
grep -F "RELEASE_TAG: \${{ inputs.tag }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE: \${{ inputs.verify_no_overwrite && '1' || '0' }}" "$workflow" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_MIN_PARITY: \${{ inputs.min_parity }}" "$workflow" >/dev/null
grep -F "BENCH_FILES: \${{ inputs.bench_files }}" "$workflow" >/dev/null
grep -F -- '--verify-no-overwrite "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"' "$workflow" >/dev/null
grep -F -- '--min-parity "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"' "$workflow" >/dev/null
grep -F -- '--bench-files "$BENCH_FILES"' "$workflow" >/dev/null
grep -F -- '--crates-install-script "$VERIFY_CRATES_INSTALL_SCRIPT"' "$workflow" >/dev/null
grep -F 'args+=(--allow-missing-crates)' "$workflow" >/dev/null
grep -F 'python3 scripts/check-public-audit-log.py "${args[@]}" public-audit.log' "$workflow" >/dev/null
grep -F "Generate release evidence" "$workflow" >/dev/null
grep -F "VERSION: \${{ inputs.version }}" "$workflow" >/dev/null
grep -F "RELEASE_TAG: \${{ inputs.tag }}" "$workflow" >/dev/null
grep -F -- '--public-audit-channels "$VERIFY_PUBLIC_INSTALL_CHANNELS"' "$workflow" >/dev/null
grep -F "set -euo pipefail" "$workflow" >/dev/null
grep -F -- '--public-audit-allow-missing-crates "$VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"' "$workflow" >/dev/null
grep -F -- '--public-audit-no-overwrite "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"' "$workflow" >/dev/null
grep -F -- '--public-audit-min-parity "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"' "$workflow" >/dev/null
grep -F -- '--public-audit-bench-files "$BENCH_FILES"' "$workflow" >/dev/null
grep -F -- '--public-audit-crates-install-script "$VERIFY_CRATES_INSTALL_SCRIPT"' "$workflow" >/dev/null
grep -F "uses: actions/upload-artifact@v4" "$workflow" >/dev/null
grep -F "name: release-evidence" "$workflow" >/dev/null
grep -F "path: |" "$workflow" >/dev/null
grep -F "release-evidence.md" "$workflow" >/dev/null
grep -F "public-audit.log" "$workflow" >/dev/null
grep -F "ref: \${{ inputs.tag }}" "$workflow" >/dev/null
grep -F "group: public-install-audit-\${{ inputs.tag }}" "$workflow" >/dev/null
grep -F "cancel-in-progress: false" "$workflow" >/dev/null

python3 - <<'PY'
from pathlib import Path
import yaml

path = Path(".github/workflows/public-install-audit.yml")
data = yaml.safe_load(path.read_text(encoding="utf-8"))
on_block = data.get("on", data.get(True))
assert on_block["workflow_dispatch"]["inputs"]["verify_no_overwrite"]["default"] is True
assert on_block["workflow_dispatch"]["inputs"]["allow_missing_crates"]["default"] is False
assert on_block["workflow_dispatch"]["inputs"]["channels"]["default"] == "github-linux github-parity bioconda crates"
assert on_block["workflow_dispatch"]["inputs"]["bench_files"]["default"] == "human_chr1 human_chr21 yeast"
assert on_block["workflow_dispatch"]["inputs"]["min_parity"]["default"] == "100"
assert on_block["workflow_dispatch"]["inputs"]["crates_install_script"]["default"] == "scripts/verify-crates-install.sh"
assert (
    on_block["workflow_dispatch"]["inputs"]["crates_install_script"]["description"]
    == "Repository-relative Crates.io install verifier script under scripts/*.sh"
)
assert data["permissions"]["contents"] == "read"
assert data["concurrency"]["group"] == "public-install-audit-${{ inputs.tag }}"
assert data["concurrency"]["cancel-in-progress"] is False
assert data["jobs"]["audit"]["timeout-minutes"] == 90
steps = data["jobs"]["audit"]["steps"]
runs = [step.get("run", "") for step in steps if isinstance(step, dict)]
assert steps[0]["name"] == "Validate workflow inputs"
assert "Version must look like X.Y.Z" in steps[0]["run"]
assert "Version and tag disagree" in steps[0]["run"]
checkout = steps[1]
assert checkout["uses"] == "actions/checkout@v4"
assert checkout["with"]["ref"] == "${{ inputs.tag }}"
assert any("verify-public-installs.sh 2>&1 | tee public-audit.log" in run for run in runs)
assert any("audit_rc=${PIPESTATUS[0]}" in run for run in runs)
assert any("public-audit-exit-code=${audit_rc}" in run for run in runs)
assert not any('exit "$audit_rc"' in run for run in runs)
assert any(
    "Audit exit code is recorded; the log validation step enforces final status."
    in run
    for run in runs
)
assert any("check-public-audit-log.py" in run and '"${args[@]}" public-audit.log' in run for run in runs)
assert any("--public-audit-log public-audit.log" in run for run in runs)
assert any("set -euo pipefail" in run and "--public-audit-log public-audit.log" in run for run in runs)
assert any('--public-audit-channels "$VERIFY_PUBLIC_INSTALL_CHANNELS"' in run for run in runs)
assert any(
    '--public-audit-allow-missing-crates "$VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"' in run
    for run in runs
)
assert any('--public-audit-no-overwrite "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"' in run for run in runs)
assert any('--public-audit-min-parity "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"' in run for run in runs)
assert any('--public-audit-bench-files "$BENCH_FILES"' in run for run in runs)
assert any('--public-audit-crates-install-script "$VERIFY_CRATES_INSTALL_SCRIPT"' in run for run in runs)
validate_steps = [
    step for step in steps
    if isinstance(step, dict) and step.get("name") == "Validate public audit log"
]
assert len(validate_steps) == 1
assert validate_steps[0]["if"] == "always()"
assert validate_steps[0]["env"]["VERSION"] == "${{ inputs.version }}"
assert validate_steps[0]["env"]["RELEASE_TAG"] == "${{ inputs.tag }}"
assert validate_steps[0]["env"]["VERIFY_PUBLIC_INSTALL_CHANNELS"] == "${{ inputs.channels }}"
assert validate_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"] == (
    "${{ inputs.allow_missing_crates && '1' || '0' }}"
)
assert validate_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"] == (
    "${{ inputs.verify_no_overwrite && '1' || '0' }}"
)
assert validate_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_MIN_PARITY"] == "${{ inputs.min_parity }}"
assert validate_steps[0]["env"]["BENCH_FILES"] == "${{ inputs.bench_files }}"
assert validate_steps[0]["env"]["VERIFY_CRATES_INSTALL_SCRIPT"] == "${{ inputs.crates_install_script }}"
assert '--verify-no-overwrite "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"' in validate_steps[0]["run"]
assert '--min-parity "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"' in validate_steps[0]["run"]
assert '--bench-files "$BENCH_FILES"' in validate_steps[0]["run"]
assert '--crates-install-script "$VERIFY_CRATES_INSTALL_SCRIPT"' in validate_steps[0]["run"]
assert "args+=(--allow-missing-crates)" in validate_steps[0]["run"]
assert 'check-public-audit-log.py "${args[@]}" public-audit.log' in validate_steps[0]["run"]
verify_input_steps = [
    step for step in steps
    if isinstance(step, dict) and step.get("name") == "Verify inputs"
]
assert len(verify_input_steps) == 1
assert verify_input_steps[0]["env"]["VERSION"] == "${{ inputs.version }}"
assert verify_input_steps[0]["env"]["RELEASE_TAG"] == "${{ inputs.tag }}"
assert verify_input_steps[0]["env"]["VERIFY_PUBLIC_INSTALL_CHANNELS"] == "${{ inputs.channels }}"
assert verify_input_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"] == (
    "${{ inputs.allow_missing_crates && '1' || '0' }}"
)
assert verify_input_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"] == (
    "${{ inputs.verify_no_overwrite && '1' || '0' }}"
)
assert verify_input_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_MIN_PARITY"] == "${{ inputs.min_parity }}"
assert verify_input_steps[0]["env"]["BENCH_FILES"] == "${{ inputs.bench_files }}"
assert verify_input_steps[0]["env"]["VERIFY_CRATES_INSTALL_SCRIPT"] == "${{ inputs.crates_install_script }}"
assert "VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 bash scripts/verify-public-installs.sh >/dev/null" in verify_input_steps[0]["run"]
evidence_steps = [
    step for step in steps
    if isinstance(step, dict) and step.get("name") == "Generate release evidence"
]
assert len(evidence_steps) == 1
assert evidence_steps[0]["if"] == "always()"
assert evidence_steps[0]["env"]["VERSION"] == "${{ inputs.version }}"
assert evidence_steps[0]["env"]["RELEASE_TAG"] == "${{ inputs.tag }}"
assert evidence_steps[0]["env"]["VERIFY_PUBLIC_INSTALL_CHANNELS"] == "${{ inputs.channels }}"
assert evidence_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"] == (
    "${{ inputs.allow_missing_crates && '1' || '0' }}"
)
assert evidence_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"] == (
    "${{ inputs.verify_no_overwrite && '1' || '0' }}"
)
assert evidence_steps[0]["env"]["VERIFY_PUBLIC_INSTALLS_MIN_PARITY"] == "${{ inputs.min_parity }}"
assert evidence_steps[0]["env"]["BENCH_FILES"] == "${{ inputs.bench_files }}"
assert evidence_steps[0]["env"]["VERIFY_CRATES_INSTALL_SCRIPT"] == "${{ inputs.crates_install_script }}"
assert '--public-audit-crates-install-script "$VERIFY_CRATES_INSTALL_SCRIPT"' in evidence_steps[0]["run"]
uploads = [
    step for step in steps
    if isinstance(step, dict) and step.get("uses", "").startswith("actions/upload-artifact")
]
assert len(uploads) == 1
assert uploads[0]["if"] == "always()"
assert uploads[0]["with"]["name"] == "release-evidence"
assert "release-evidence.md" in uploads[0]["with"]["path"]
assert "public-audit.log" in uploads[0]["with"]["path"]
PY

echo "verified public install audit workflow"
