#!/usr/bin/env bash
# Regression tests for scripts/verify-public-installs.sh dry-run behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
missing_crates_script="scripts/.test-missing-crates-$$.sh"
broken_crates_script="scripts/.test-broken-crates-$$.sh"
trap 'rm -rf "$tmp"; rm -f "$missing_crates_script" "$broken_crates_script"' EXIT

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

VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 \
  VERSION=1.2.3 \
  RELEASE_TAG=v1.2.3 \
  VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
  VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
  VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
  bash scripts/verify-public-installs.sh >"$tmp/dry-run.out"

grep -F "version=1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "tag=v1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "channels=github-linux github-parity bioconda crates" "$tmp/dry-run.out" >/dev/null
grep -F "allow_missing_crates=1" "$tmp/dry-run.out" >/dev/null
grep -F "verify_no_overwrite=1" "$tmp/dry-run.out" >/dev/null
grep -F "min_parity=100" "$tmp/dry-run.out" >/dev/null
grep -F "bench_files=human_chr1 human_chr21 yeast" "$tmp/dry-run.out" >/dev/null
grep -F "crates_install_script=scripts/verify-crates-install.sh" "$tmp/dry-run.out" >/dev/null
grep -F "github-linux=RELEASE_TAG=v1.2.3 VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE=1 bash scripts/verify-github-release-linux-docker.sh" \
  "$tmp/dry-run.out" >/dev/null
grep -F "github-parity=RELEASE_TAG=v1.2.3 BENCH_FILES=human_chr1\\ human_chr21\\ yeast MIN_PARITY=100 bash scripts/verify-github-release-parity.sh" \
  "$tmp/dry-run.out" >/dev/null
grep -F "bioconda=VERSION=1.2.3 VERIFY_BIOCONDA_NO_OVERWRITE=1 bash scripts/verify-bioconda-install.sh" \
  "$tmp/dry-run.out" >/dev/null
grep -F "crates=VERSION=1.2.3 bash scripts/verify-crates-install.sh" \
  "$tmp/dry-run.out" >/dev/null

VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 \
  VERSION=1.2.3 \
  RELEASE_TAG=v1.2.3 \
  VERIFY_PUBLIC_INSTALL_CHANNELS="github-parity" \
  VERIFY_PUBLIC_INSTALLS_MIN_PARITY=99.5 \
  bash scripts/verify-public-installs.sh >"$tmp/min-parity-dry-run.out"
grep -F "min_parity=99.5" "$tmp/min-parity-dry-run.out" >/dev/null
grep -F "BENCH_FILES=human_chr1\\ human_chr21\\ yeast MIN_PARITY=99.5 bash scripts/verify-github-release-parity.sh" \
  "$tmp/min-parity-dry-run.out" >/dev/null

VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 \
  VERSION=1.2.3 \
  RELEASE_TAG=v1.2.3 \
  bash scripts/verify-public-installs.sh >"$tmp/default-strict-dry-run.out"
grep -F "channels=github-linux github-parity bioconda crates" "$tmp/default-strict-dry-run.out" >/dev/null
grep -F "verify_no_overwrite=1" "$tmp/default-strict-dry-run.out" >/dev/null
grep -F "min_parity=100" "$tmp/default-strict-dry-run.out" >/dev/null
grep -F "github-linux=RELEASE_TAG=v1.2.3 VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE=1 bash scripts/verify-github-release-linux-docker.sh" \
  "$tmp/default-strict-dry-run.out" >/dev/null
grep -F "bioconda=VERSION=1.2.3 VERIFY_BIOCONDA_NO_OVERWRITE=1 bash scripts/verify-bioconda-install.sh" \
  "$tmp/default-strict-dry-run.out" >/dev/null

expect_fail \
  bad-tag \
  "release tag must start with v" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=1.2.3 \
    bash scripts/verify-public-installs.sh

expect_fail \
  bad-version \
  "version must look like X.Y.Z" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=nope RELEASE_TAG=vnope \
    bash scripts/verify-public-installs.sh

expect_fail \
  tag-version-mismatch \
  "VERSION and RELEASE_TAG disagree" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.4 \
    bash scripts/verify-public-installs.sh

expect_fail \
  bad-dry-run \
  "VERIFY_PUBLIC_INSTALLS_DRY_RUN must be 0 or 1" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=maybe VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    bash scripts/verify-public-installs.sh

expect_fail \
  bad-allow-missing \
  "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES must be 0 or 1" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=maybe \
    RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh

expect_fail \
  allow-missing-without-crates \
  "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 requires the crates channel" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_PUBLIC_INSTALL_CHANNELS=github-parity VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
    bash scripts/verify-public-installs.sh

expect_fail \
  bad-no-overwrite \
  "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE must be 0 or 1" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=maybe \
    RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh

expect_fail \
  bad-channel \
  "unknown public install channel" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 VERIFY_PUBLIC_INSTALL_CHANNELS=unknown \
    RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh

expect_fail \
  empty-channels \
  "VERIFY_PUBLIC_INSTALL_CHANNELS must include at least one channel" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 VERIFY_PUBLIC_INSTALL_CHANNELS="   " \
    RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh

expect_fail \
  duplicate-channel \
  "duplicate public install channel: crates" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 VERIFY_PUBLIC_INSTALL_CHANNELS="crates crates" \
    RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh

expect_fail \
  bad-min-parity \
  "VERIFY_PUBLIC_INSTALLS_MIN_PARITY must be a number" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_PUBLIC_INSTALLS_MIN_PARITY=high bash scripts/verify-public-installs.sh

expect_fail \
  too-high-min-parity \
  "VERIFY_PUBLIC_INSTALLS_MIN_PARITY must be between 0 and 100" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_PUBLIC_INSTALLS_MIN_PARITY=101 bash scripts/verify-public-installs.sh

expect_fail \
  empty-bench-files \
  "BENCH_FILES must include at least one corpus name" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    BENCH_FILES="   " bash scripts/verify-public-installs.sh

expect_fail \
  duplicate-bench-file \
  "duplicate BENCH_FILES entry: yeast" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    BENCH_FILES="yeast yeast" bash scripts/verify-public-installs.sh

expect_fail \
  unsafe-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    BENCH_FILES="../yeast" bash scripts/verify-public-installs.sh

expect_fail \
  dot-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    BENCH_FILES="." bash scripts/verify-public-installs.sh

expect_fail \
  glob-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    BENCH_FILES="*" bash scripts/verify-public-installs.sh

expect_fail \
  glob-channel \
  "unknown public install channel: *" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_PUBLIC_INSTALL_CHANNELS="*" bash scripts/verify-public-installs.sh

expect_fail \
  absolute-crates-script \
  "VERIFY_CRATES_INSTALL_SCRIPT must be a repository-relative scripts/*.sh path" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_CRATES_INSTALL_SCRIPT="$tmp/missing-crates.sh" bash scripts/verify-public-installs.sh

expect_fail \
  traversal-crates-script \
  "VERIFY_CRATES_INSTALL_SCRIPT must be a repository-relative scripts/*.sh path" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_CRATES_INSTALL_SCRIPT="scripts/../verify-crates-install.sh" bash scripts/verify-public-installs.sh

expect_fail \
  missing-crates-script \
  "VERIFY_CRATES_INSTALL_SCRIPT does not exist" \
  env VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    VERIFY_CRATES_INSTALL_SCRIPT="scripts/.does-not-exist-crates.sh" bash scripts/verify-public-installs.sh

cat >"$missing_crates_script" <<'SH'
#!/usr/bin/env bash
echo 'error: could not find `gxfkit` in registry `crates-io` with version `=1.2.3`' >&2
exit 101
SH
cat >"$broken_crates_script" <<'SH'
#!/usr/bin/env bash
echo 'network timeout while downloading dependency' >&2
exit 101
SH
chmod +x "$missing_crates_script" "$broken_crates_script"

VERIFY_PUBLIC_INSTALL_CHANNELS=crates \
  VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
  VERIFY_CRATES_INSTALL_SCRIPT="$missing_crates_script" \
  VERSION=1.2.3 \
  RELEASE_TAG=v1.2.3 \
  bash scripts/verify-public-installs.sh >"$tmp/missing-ok.out" 2>&1
grep -F "public-audit-version=1.2.3" "$tmp/missing-ok.out" >/dev/null
grep -F "public-audit-tag=v1.2.3" "$tmp/missing-ok.out" >/dev/null
grep -F "public-audit-channels=crates" "$tmp/missing-ok.out" >/dev/null
grep -F "public-audit-crates-install-script=$missing_crates_script" "$tmp/missing-ok.out" >/dev/null
grep -F "allowed_missing=[crates ]" "$tmp/missing-ok.out" >/dev/null

expect_fail \
  broken-crates-not-allowed \
  "failed=[crates ]" \
  env VERIFY_PUBLIC_INSTALL_CHANNELS=crates VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
    VERIFY_CRATES_INSTALL_SCRIPT="$broken_crates_script" VERSION=1.2.3 RELEASE_TAG=v1.2.3 \
    bash scripts/verify-public-installs.sh

echo "verified public install verifier tests"
