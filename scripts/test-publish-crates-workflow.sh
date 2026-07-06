#!/usr/bin/env bash
# Regression checks for the manual Crates.io publish workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

workflow=".github/workflows/publish-crates.yml"
test -f "$workflow"

grep -F "name: Publish Crates.io" "$workflow" >/dev/null
grep -F "workflow_dispatch:" "$workflow" >/dev/null
grep -F "source_ref:" "$workflow" >/dev/null
grep -F "defaults to v<version>" "$workflow" >/dev/null
grep -F "PUBLISH_REF: \${{ inputs.source_ref || format('v{0}', inputs.version) }}" "$workflow" >/dev/null
grep -F "ref: \${{ env.PUBLISH_REF }}" "$workflow" >/dev/null
grep -F "group: publish-crates-\${{ inputs.version }}" "$workflow" >/dev/null
grep -F "cancel-in-progress: false" "$workflow" >/dev/null
grep -F "confirm:" "$workflow" >/dev/null
grep -F "Type 'publish' to publish to Crates.io" "$workflow" >/dev/null
grep -F "Verify publish inputs" "$workflow" >/dev/null
grep -F "Workspace version must look like X.Y.Z" "$workflow" >/dev/null
grep -F "Publish ref must be non-empty and contain no whitespace" "$workflow" >/dev/null
grep -F "CARGO_REGISTRY_TOKEN: \${{ secrets.CARGO_REGISTRY_TOKEN }}" "$workflow" >/dev/null
grep -F "Verify Crates.io token" "$workflow" >/dev/null
grep -F 'if [ -z "${CARGO_REGISTRY_TOKEN:-}" ]; then' "$workflow" >/dev/null
grep -F "CARGO_REGISTRY_TOKEN repository secret is required to publish to Crates.io." "$workflow" >/dev/null
grep -F "VERSION=\"\${EXPECTED_VERSION}\" bash scripts/check-publish-ref.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-version-consistency.py" "$workflow" >/dev/null
grep -F "bash scripts/test-crate-metadata.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-crate-metadata.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-artifacts.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-artifacts.py" "$workflow" >/dev/null
grep -F "bash scripts/test-github-source-sha256.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-release-readiness.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-release-evidence.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-local-cargo-install-verifier.sh" "$workflow" >/dev/null
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
grep -F "bash scripts/test-release-notes.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-notes.py" "$workflow" >/dev/null
grep -F "bash scripts/test-install-docs.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-install-docs.py" "$workflow" >/dev/null
grep -F "bash scripts/test-release-doc.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-release-doc.py" "$workflow" >/dev/null
grep -F -- "--scope cargo" "$workflow" >/dev/null
grep -F -- "--expected-version \"\$EXPECTED_VERSION\"" "$workflow" >/dev/null
grep -F "bash scripts/test-publish-crates-workflow.sh" "$workflow" >/dev/null
grep -F "bash scripts/test-workflow-policy.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-workflow-policy.py" "$workflow" >/dev/null
grep -F "bash scripts/test-benchmark-summary.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-benchmark-summary.py" "$workflow" >/dev/null
grep -F "bash scripts/test-parity-doc.sh" "$workflow" >/dev/null
grep -F "python3 scripts/check-parity-doc.py" "$workflow" >/dev/null
grep -F "bash scripts/test-package-files.sh" "$workflow" >/dev/null
grep -F "PACKAGE_FILES_ALLOW_DIRTY=0 bash scripts/check-package-files.sh" "$workflow" >/dev/null
grep -F "cargo package -p gxfkit-core --locked --registry crates-io" "$workflow" >/dev/null
grep -F "cargo publish -p gxfkit-core --locked --registry crates-io" "$workflow" >/dev/null
grep -F "inputs.crate == 'both' || inputs.crate == 'gxfkit-core' || inputs.crate == 'gxfkit'" \
  "$workflow" >/dev/null
grep -F "cargo search gxfkit-core --registry crates-io --limit 5" "$workflow" >/dev/null
grep -F "cargo package -p gxfkit --locked --registry crates-io" "$workflow" >/dev/null
grep -F "cargo publish -p gxfkit --locked --registry crates-io" "$workflow" >/dev/null
grep -F "cargo search gxfkit --registry crates-io --limit 5" "$workflow" >/dev/null
grep -F "VERSION=\"\${EXPECTED_VERSION}\" bash scripts/verify-crates-install.sh" "$workflow" >/dev/null

python3 - <<'PY'
from pathlib import Path
import yaml

path = Path(".github/workflows/publish-crates.yml")
data = yaml.safe_load(path.read_text(encoding="utf-8"))
on_block = data.get("on", data.get(True))
inputs = on_block["workflow_dispatch"]["inputs"]
assert set(inputs) == {"version", "crate", "source_ref", "confirm"}
assert inputs["version"]["required"] is True
assert inputs["crate"]["default"] == "both"
assert inputs["crate"]["options"] == ["both", "gxfkit-core", "gxfkit"]
assert inputs["source_ref"]["required"] is False
assert inputs["source_ref"]["default"] == ""
assert inputs["confirm"]["required"] is True
assert data["permissions"]["contents"] == "read"
assert data["concurrency"]["group"] == "publish-crates-${{ inputs.version }}"
assert data["concurrency"]["cancel-in-progress"] is False
assert data["env"]["EXPECTED_VERSION"] == "${{ inputs.version }}"
assert data["env"]["PUBLISH_REF"] == "${{ inputs.source_ref || format('v{0}', inputs.version) }}"
assert data["jobs"]["publish"]["timeout-minutes"] == 45

steps = data["jobs"]["publish"]["steps"]
runs = [step.get("run", "") for step in steps if isinstance(step, dict)]
names = [step.get("name", "") for step in steps if isinstance(step, dict)]
assert steps[0]["name"] == "Verify publish inputs"
assert steps[1]["name"] == "Verify Crates.io token"
checkout = next(step for step in steps if isinstance(step, dict) and step.get("uses") == "actions/checkout@v4")
checkout_index = steps.index(checkout)
assert checkout["uses"] == "actions/checkout@v4"
assert checkout["with"]["ref"] == "${{ env.PUBLISH_REF }}"
assert "Verify publish inputs" in names
assert "Verify Crates.io token" in names
assert "Verify workspace crate versions" in names
assert "Verify publish ref" in names
assert "Run publish preflight" in names
assert "Publish gxfkit-core" in names
assert "Wait for gxfkit-core registry visibility" in names
assert "Package gxfkit" in names
assert "Publish gxfkit" in names
assert "Wait for gxfkit registry visibility" in names
assert "Verify Crates.io install" in names

input_run = next(run for run in runs if "Workspace version must look like X.Y.Z" in run)
assert 'CONFIRM" != "publish"' in input_run
assert "Publish ref must be non-empty and contain no whitespace" in input_run
assert "exit 1" in input_run
preflight = next(run for run in runs if "cargo fmt --all --check" in run)
for required in [
    "cargo clippy --locked --all-targets -- -D warnings",
    "cargo test --all --locked",
    "cargo build --release --locked --bin gxfkit",
    "bash scripts/verify-local-cargo-install.sh",
    "bash scripts/test-local-cargo-install-verifier.sh",
    "bash scripts/test-crate-metadata.sh",
    "python3 scripts/check-crate-metadata.py",
    "bash scripts/test-release-artifacts.sh",
    "python3 scripts/check-release-artifacts.py",
    "bash scripts/test-public-install-audit-workflow.sh",
    "bash scripts/test-ci-workflow.sh",
    "bash scripts/test-release-workflow.sh",
    "bash scripts/test-publish-crates-workflow.sh",
    "bash scripts/test-workflow-policy.sh",
    "python3 scripts/check-workflow-policy.py",
    "bash scripts/test-github-source-sha256.sh",
    "bash scripts/test-version-consistency.sh",
    "bash scripts/test-release-readiness.sh",
    "bash scripts/test-release-evidence.sh",
    "bash scripts/test-maintainer-surfaces.sh",
    "python3 scripts/check-maintainer-surfaces.py",
    "bash scripts/test-shell-syntax.sh",
    "python3 scripts/test-python-syntax.py",
    "bash scripts/test-release-check.sh",
    "python3 scripts/check-release-check.py",
    "bash scripts/test-release-check-log.sh",
    "bash scripts/test-repo-hygiene.sh",
    "bash scripts/test-executable-scripts.sh",
    "bash scripts/test-public-audit-log.sh",
    "bash scripts/test-release-notes.sh",
    "python3 scripts/check-release-notes.py",
    "bash scripts/test-install-docs.sh",
    "python3 scripts/check-install-docs.py",
    "bash scripts/test-release-doc.sh",
    "python3 scripts/check-release-doc.py",
    "bash scripts/test-benchmark-summary.sh",
    "python3 scripts/check-benchmark-summary.py",
    "bash scripts/test-parity-doc.sh",
    "python3 scripts/check-parity-doc.py",
    "bash scripts/test-package-files.sh",
    "PACKAGE_FILES_ALLOW_DIRTY=0 bash scripts/check-package-files.sh",
    "python3 scripts/check-version-consistency.py",
    "--scope cargo",
    "--expected-version \"$EXPECTED_VERSION\"",
    "cargo package -p gxfkit-core --locked --registry crates-io",
]:
    assert required in preflight, required

step_by_name = {
    step.get("name"): step
    for step in steps
    if isinstance(step, dict) and step.get("name")
}
token_step = step_by_name["Verify Crates.io token"]
assert token_step["env"]["CARGO_REGISTRY_TOKEN"] == "${{ secrets.CARGO_REGISTRY_TOKEN }}"
assert 'if [ -z "${CARGO_REGISTRY_TOKEN:-}" ]; then' in token_step["run"]
assert "repository secret is required to publish to Crates.io" in token_step["run"]
assert (
    step_by_name["Publish gxfkit-core"]["env"]["CARGO_REGISTRY_TOKEN"]
    == "${{ secrets.CARGO_REGISTRY_TOKEN }}"
)
assert (
    step_by_name["Publish gxfkit"]["env"]["CARGO_REGISTRY_TOKEN"]
    == "${{ secrets.CARGO_REGISTRY_TOKEN }}"
)
assert step_by_name["Publish gxfkit-core"]["run"] == (
    "cargo publish -p gxfkit-core --locked --registry crates-io"
)
assert step_by_name["Publish gxfkit"]["run"] == (
    "cargo publish -p gxfkit --locked --registry crates-io"
)
assert "cargo search gxfkit-core" in step_by_name[
    "Wait for gxfkit-core registry visibility"
]["run"]
assert "EXPECTED_VERSION" in step_by_name[
    "Wait for gxfkit-core registry visibility"
]["run"]
assert step_by_name["Wait for gxfkit-core registry visibility"]["if"] == (
    "${{ inputs.crate == 'both' || inputs.crate == 'gxfkit-core' || inputs.crate == 'gxfkit' }}"
)
assert "cargo search gxfkit " in step_by_name[
    "Wait for gxfkit registry visibility"
]["run"]
assert "verify-crates-install.sh" in step_by_name["Verify Crates.io install"]["run"]

ordered_names = [
    step.get("name")
    for step in steps
    if isinstance(step, dict) and step.get("name")
]
assert ordered_names.index("Verify publish inputs") < ordered_names.index(
    "Verify Crates.io token"
)
assert ordered_names.index("Verify Crates.io token") < checkout_index
assert ordered_names.index("Verify Crates.io token") < ordered_names.index(
    "Verify workspace crate versions"
)
assert ordered_names.index("Publish gxfkit-core") < ordered_names.index(
    "Wait for gxfkit-core registry visibility"
)
assert ordered_names.index("Wait for gxfkit-core registry visibility") < ordered_names.index(
    "Package gxfkit"
)
assert ordered_names.index("Package gxfkit") < ordered_names.index("Publish gxfkit")
assert ordered_names.index("Publish gxfkit") < ordered_names.index(
    "Wait for gxfkit registry visibility"
)
assert ordered_names.index("Wait for gxfkit registry visibility") < ordered_names.index(
    "Verify Crates.io install"
)
PY

echo "verified Crates.io publish workflow"
