#!/usr/bin/env bash
# Regression tests for scripts/check-release-doc.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 scripts/check-release-doc.py

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
  if ! grep -F "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

fixture="$tmp/fixture"
mkdir -p "$fixture/docs"
cp docs/RELEASE.md "$fixture/docs/RELEASE.md"

perl -0pi -e 's/set \+e\nRELEASE_CHECK_VERSION_SCOPE=cargo bash scripts\/release-check\.sh > release-check\.log 2>&1\nrc=\$\?\nprintf '\''release-check-exit-code=%s\\n'\'' "\$rc" >> release-check\.log\nset -e\nscripts\/release-evidence\.sh --allow-dirty --release-check-log release-check\.log > release-evidence\.md\nexit "\$rc"//' \
  "$fixture/docs/RELEASE.md"
expect_fail \
  missing-evidence-command \
  "docs/RELEASE.md must mention: scripts/release-evidence.sh --allow-dirty --release-check-log release-check.log > release-evidence.md" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
perl -0pi -e 's/VERSION=X\.Y\.Z RELEASE_TAG=vX\.Y\.Z bash scripts\/verify-public-installs\.sh//g' \
  "$fixture/docs/RELEASE.md"
expect_fail \
  missing-public-audit-command \
  "docs/RELEASE.md must mention: VERSION=X.Y.Z RELEASE_TAG=vX.Y.Z bash scripts/verify-public-installs.sh" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
perl -0pi -e 's/python3 scripts\/release-readiness\.py --phase public --check-public --run-public-audit//g' \
  "$fixture/docs/RELEASE.md"
expect_fail \
  missing-readiness-public-audit \
  "docs/RELEASE.md must mention: python3 scripts/release-readiness.py --phase public --check-public --run-public-audit" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
perl -0pi -e 's/explicitly `yanked: false`, and//' \
  "$fixture/docs/RELEASE.md"
expect_fail \
  missing-crates-yanked-false \
  'docs/RELEASE.md must mention: Crates.io versions to be present, explicitly `yanked: false`' \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
perl -0pi -e 's/Local `release-check\.sh` runs its final `cargo package` smoke in\s+offline mode//' \
  "$fixture/docs/RELEASE.md"
expect_fail \
  missing-offline-package-smoke \
  'docs/RELEASE.md must mention: Local `release-check.sh` runs its final `cargo package` smoke in offline mode' \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
printf '\nMIN_PARITY=98\n' >>"$fixture/docs/RELEASE.md"
expect_fail \
  forbidden-old-parity \
  "docs/RELEASE.md must not mention: MIN_PARITY=98" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

cp docs/RELEASE.md "$fixture/docs/RELEASE.md"
perl -0pi -e 's/```bash\n//' "$fixture/docs/RELEASE.md"
expect_fail \
  unbalanced-fences \
  "docs/RELEASE.md must have balanced fenced code blocks" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-doc.py

echo "verified release guide tests"
