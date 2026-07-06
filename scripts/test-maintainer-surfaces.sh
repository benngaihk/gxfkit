#!/usr/bin/env bash
# Regression tests for scripts/check-maintainer-surfaces.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python >/dev/null 2>&1; then
    PY=python
  else
    PY=python3
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_fail() {
  local label="$1"
  local expected="$2"
  shift 2
  local out="$tmp/${label}.out"
  if "$@" >"$out" 2>&1; then
    echo "$label unexpectedly passed" >&2
    cat "$out" >&2
    exit 1
  fi
  if ! grep -F -- "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

write_issue_template() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'YAML'
name: template
body:
  - type: input
    id: version
    attributes:
      label: gxfkit version
      placeholder: "gxfkit 1.2.3"
YAML
}

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/.github/workflows" "$dir/.github/ISSUE_TEMPLATE"
  cat >"$dir/Cargo.toml" <<'TOML'
[workspace.package]
version = "1.2.3"
TOML
  write_issue_template "$dir/.github/ISSUE_TEMPLATE/bug_report.yml"
  write_issue_template "$dir/.github/ISSUE_TEMPLATE/bug_report_zh.yml"
  write_issue_template "$dir/.github/ISSUE_TEMPLATE/parity_divergence.yml"
  write_issue_template "$dir/.github/ISSUE_TEMPLATE/parity_divergence_zh.yml"
  cat >"$dir/.github/workflows/publish-crates.yml" <<'YAML'
on:
  workflow_dispatch:
    inputs:
      version:
        description: "Workspace version to publish, for example 1.2.3"
YAML
  cat >"$dir/.github/workflows/release.yml" <<'YAML'
on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Existing tag to publish, for example v1.2.3"
YAML
}

"$PY" scripts/check-maintainer-surfaces.py >"$tmp/current.out"
grep -F "verified maintainer surfaces" "$tmp/current.out" >/dev/null

fixture="$tmp/good"
make_fixture "$fixture"
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-maintainer-surfaces.py" >"$tmp/good.out"
grep -F "verified maintainer surfaces for 1.2.3" "$tmp/good.out" >/dev/null

fixture="$tmp/stale-issue-template"
make_fixture "$fixture"
perl -0pi -e 's/gxfkit 1\.2\.3/gxfkit 0.0.1/' "$fixture/.github/ISSUE_TEMPLATE/bug_report.yml"
expect_fail \
  stale-issue-template \
  ".github/ISSUE_TEMPLATE/bug_report.yml must contain: gxfkit 1.2.3" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-maintainer-surfaces.py"

fixture="$tmp/stale-publish-workflow"
make_fixture "$fixture"
perl -0pi -e 's/for example 1\.2\.3/for example 0.0.1/' \
  "$fixture/.github/workflows/publish-crates.yml"
expect_fail \
  stale-publish-workflow \
  ".github/workflows/publish-crates.yml must contain: for example 1.2.3" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-maintainer-surfaces.py"

fixture="$tmp/stale-release-workflow"
make_fixture "$fixture"
perl -0pi -e 's/for example v1\.2\.3/for example v0.1.0/' \
  "$fixture/.github/workflows/release.yml"
expect_fail \
  stale-release-workflow \
  ".github/workflows/release.yml must contain: for example v1.2.3" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-maintainer-surfaces.py"

echo "verified maintainer surfaces tests"
