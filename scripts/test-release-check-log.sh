#!/usr/bin/env bash
# Regression tests for scripts/check-release-check-log.py.
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

cat >"$tmp/ok.log" <<'LOG'
>> formatting
>> linting
>> tests
>> release build
>> local cargo install
verified local cargo install verifier tests
gxfkit 1.2.3
verified local cargo install
>> Crates.io install verifier
verified Crates.io install verifier tests
>> Crates.io metadata
verified crates.io metadata tests
verified crates.io metadata
>> release archive verifier
verified release archive verifier tests
verified release artifact contract tests
verified release artifact contract
>> GitHub release verifier
verified GitHub release verifier tests
verified GitHub release parity verifier tests
>> Bioconda recipe
verified Bioconda recipe tests
verified GitHub source sha256 helper tests
>> Bioconda install verifier
verified Bioconda install verifier tests
>> public install audit verifier
verified public install verifier tests
verified public audit log tests
verified shell script syntax
verified python script syntax
verified release-check contract
verified release-check contract tests
verified release-check log tests
verified repository hygiene ignores
verified directly executable scripts
verified public install audit workflow
verified CI workflow
verified release workflow
verified Crates.io publish workflow
verified GitHub Actions workflow policy for 4 workflow(s)
verified workflow policy guard
>> publish ref verifier
verified publish ref tests
>> benchmark summarizer
verified benchmark summarize tests
verified benchmark summary tests
>> parity doc
verified parity doc tests
verified parity doc
>> residual writer
verified residual writer tests
>> version consistency self-test
verified version consistency tests
verified prepare next version tests
>> version consistency
OK crate versions: 1.2.3
>> release status doc
verified release status doc tests
verified release status doc
verified install docs tests
verified install docs
verified release guide tests
verified release guide
verified release notes for v1.2.3
verified release notes tests
>> release readiness verifier
verified release readiness tests
verified release evidence report tests
>> maintainer surfaces
verified maintainer surfaces tests
>> publish ref
>> package file lists
verified package file list tests
>> package gxfkit-core
>> package gxfkit
gxfkit package verification did not complete.
This is expected before gxfkit-core has been published to the registry, because
the binary crate depends on gxfkit-core by version.
>> release preflight complete
release-check-exit-code=0
LOG

python3 scripts/check-release-check-log.py --version 1.2.3 "$tmp/ok.log" >"$tmp/ok.out"
grep -F "verified release-check log" "$tmp/ok.out" >/dev/null

cp "$tmp/ok.log" "$tmp/missing.log"
perl -0pi -e 's/release-check-exit-code=0\n//' "$tmp/missing.log"
expect_fail \
  missing-exit-code \
  "release-check log is missing marker: release-check-exit-code=0" \
  python3 scripts/check-release-check-log.py "$tmp/missing.log"

cp "$tmp/ok.log" "$tmp/bad-exit-code.log"
perl -0pi -e 's/release-check-exit-code=0/release-check-exit-code=101/' "$tmp/bad-exit-code.log"
expect_fail \
  bad-exit-code \
  "release-check exit code must be 0, got 101" \
  python3 scripts/check-release-check-log.py "$tmp/bad-exit-code.log"

cp "$tmp/ok.log" "$tmp/duplicate-exit-code.log"
printf 'release-check-exit-code=0\n' >>"$tmp/duplicate-exit-code.log"
expect_fail \
  duplicate-exit-code \
  "release-check log must contain exactly one release-check-exit-code line" \
  python3 scripts/check-release-check-log.py "$tmp/duplicate-exit-code.log"

cp "$tmp/ok.log" "$tmp/network.log"
printf '\nwarning: spurious network error (3 tries remaining): [28] Timeout was reached\n' \
  >>"$tmp/network.log"
expect_fail \
  network-timeout \
  "release-check log contains forbidden marker: spurious network error" \
  python3 scripts/check-release-check-log.py "$tmp/network.log"

cp "$tmp/ok.log" "$tmp/missing-release-artifact-contract.log"
perl -0pi -e 's/verified release artifact contract tests\nverified release artifact contract\n//' \
  "$tmp/missing-release-artifact-contract.log"
expect_fail \
  missing-release-artifact-contract \
  "release-check log is missing marker: verified release artifact contract tests" \
  python3 scripts/check-release-check-log.py "$tmp/missing-release-artifact-contract.log"

cp "$tmp/ok.log" "$tmp/missing-github-source-sha.log"
perl -0pi -e 's/verified GitHub source sha256 helper tests\n//' \
  "$tmp/missing-github-source-sha.log"
expect_fail \
  missing-github-source-sha \
  "release-check log is missing marker: verified GitHub source sha256 helper tests" \
  python3 scripts/check-release-check-log.py "$tmp/missing-github-source-sha.log"

cp "$tmp/ok.log" "$tmp/missing-install-docs.log"
perl -0pi -e 's/verified install docs tests\nverified install docs\n//' \
  "$tmp/missing-install-docs.log"
expect_fail \
  missing-install-docs \
  "release-check log is missing marker: verified install docs tests" \
  python3 scripts/check-release-check-log.py "$tmp/missing-install-docs.log"

cp "$tmp/ok.log" "$tmp/missing-hygiene.log"
perl -0pi -e 's/verified shell script syntax\nverified python script syntax\nverified release-check contract\nverified release-check contract tests\nverified release-check log tests\nverified repository hygiene ignores\nverified directly executable scripts\n/verified release-check contract\n/' \
  "$tmp/missing-hygiene.log"
expect_fail \
  missing-hygiene \
  "release-check log is missing marker: verified shell script syntax" \
  python3 scripts/check-release-check-log.py "$tmp/missing-hygiene.log"

cp "$tmp/ok.log" "$tmp/missing-package-result.log"
perl -0pi -e 's/gxfkit package verification did not complete\.\nThis is expected before gxfkit-core has been published to the registry, because\nthe binary crate depends on gxfkit-core by version\.\n//' \
  "$tmp/missing-package-result.log"
expect_fail \
  missing-package-result \
  "release-check log must show either successful gxfkit package verification" \
  python3 scripts/check-release-check-log.py "$tmp/missing-package-result.log"

expect_fail \
  version-mismatch \
  "release-check log must mention gxfkit 2.0.0" \
  python3 scripts/check-release-check-log.py --version 2.0.0 "$tmp/ok.log"

expect_fail \
  bad-version \
  "must look like X.Y.Z" \
  python3 scripts/check-release-check-log.py --version nope "$tmp/ok.log"

echo "verified release-check log tests"
