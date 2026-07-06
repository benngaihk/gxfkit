#!/usr/bin/env bash
# Regression tests for scripts/check-release-check.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

fixture="$tmp/fixture"
mkdir -p "$fixture/scripts"
cp scripts/release-check.sh "$fixture/scripts/release-check.sh"

python3 scripts/check-release-check.py

perl -0pi -e 's/PACKAGE_NETWORK="\$\{RELEASE_CHECK_PACKAGE_NETWORK:-0\}"/PACKAGE_NETWORK="${RELEASE_CHECK_PACKAGE_NETWORK:-1}"/' \
  "$fixture/scripts/release-check.sh"
expect_fail \
  default-online-package \
  'scripts/release-check.sh must contain: PACKAGE_NETWORK="${RELEASE_CHECK_PACKAGE_NETWORK:-0}"' \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
perl -0pi -e 's/package_args\+=\(--offline\)//' "$fixture/scripts/release-check.sh"
expect_fail \
  missing-offline-package-arg \
  "scripts/release-check.sh must contain: package_args+=(--offline)" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
perl -0pi -e 's/VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="\$CARGO_BIN" bash scripts\/verify-local-cargo-install\.sh/CARGO="$CARGO_BIN" bash scripts\/verify-local-cargo-install.sh/' \
  "$fixture/scripts/release-check.sh"
expect_fail \
  local-install-networked \
  'scripts/release-check.sh must contain: VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="$CARGO_BIN" bash scripts/verify-local-cargo-install.sh' \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
perl -0pi -e 's/bash scripts\/test-release-artifacts\.sh\n//' "$fixture/scripts/release-check.sh"
expect_fail \
  missing-release-artifact-tests \
  "scripts/release-check.sh must contain: bash scripts/test-release-artifacts.sh" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
perl -0pi -e 's/python3 scripts\/check-release-artifacts\.py\n//' "$fixture/scripts/release-check.sh"
expect_fail \
  missing-release-artifact-check \
  "scripts/release-check.sh must contain: python3 scripts/check-release-artifacts.py" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
touch "$fixture/scripts/test-new-production-gate.sh"
expect_fail \
  missing-new-test-script \
  "scripts/release-check.sh must contain: scripts/test-new-production-gate.sh" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

cp scripts/release-check.sh "$fixture/scripts/release-check.sh"
printf '\nPACKAGE_CARGO_HOME="$(mktemp -d)"\n' >>"$fixture/scripts/release-check.sh"
expect_fail \
  clean-cargo-home-regression \
  "scripts/release-check.sh must not contain: PACKAGE_CARGO_HOME" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-release-check.py

echo "verified release-check contract tests"
