#!/usr/bin/env bash
# Regression tests for scripts/check-crates-publish-state.sh.
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

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w)
      shift 2
      ;;
    -H)
      shift 2
      ;;
    --connect-timeout | --max-time)
      shift 2
      ;;
    -sS | -L)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
case "$url" in
  */crates/gxfkit-core/*)
    state="${GXFKIT_FAKE_CRATES_GXFKIT_CORE:-absent}"
    ;;
  */crates/gxfkit/*)
    if [ "${GXFKIT_FAIL_ON_GXFKIT_QUERY:-0}" = 1 ]; then
      echo "unexpected gxfkit query" >&2
      exit 2
    fi
    state="${GXFKIT_FAKE_CRATES_GXFKIT:-absent}"
    ;;
  *)
    echo "unexpected curl URL: $url" >&2
    exit 2
    ;;
esac
case "$state" in
  absent)
    : >"$out"
    printf '404'
    ;;
  present)
    printf '{"version":{"yanked":false}}\n' >"$out"
    printf '200'
    ;;
  yanked)
    printf '{"version":{"yanked":true}}\n' >"$out"
    printf '200'
    ;;
  error)
    printf '{"error":"boom"}\n' >"$out"
    printf '500'
    ;;
  *)
    echo "unexpected fake Crates.io state: $state" >&2
    exit 2
    ;;
esac
SH
chmod +x "$fake_bin/curl"

expect_fail \
  bad-version \
  "VERSION must look like X.Y.Z, got: nope" \
  env PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh nope both

expect_fail \
  bad-crate \
  "crate scope must be one of: both, gxfkit-core, gxfkit; got: bad" \
  env PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 bad

expect_fail \
  bad-connect-timeout \
  "GXFKIT_CRATES_IO_CONNECT_TIMEOUT must be a positive integer, got: nope" \
  env GXFKIT_CRATES_IO_CONNECT_TIMEOUT=nope PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 both

expect_fail \
  bad-max-time \
  "GXFKIT_CRATES_IO_MAX_TIME must be a positive integer, got: 0" \
  env GXFKIT_CRATES_IO_MAX_TIME=0 PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 both

env PATH="$fake_bin:$PATH" \
  bash scripts/check-crates-publish-state.sh 1.2.3 both \
  >"$tmp/both-ok.out"
grep -F "verified Crates.io publish state for both 1.2.3" "$tmp/both-ok.out" >/dev/null

env GXFKIT_FAIL_ON_GXFKIT_QUERY=1 PATH="$fake_bin:$PATH" \
  bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit-core \
  >"$tmp/core-ok.out"
grep -F "verified Crates.io publish state for gxfkit-core 1.2.3" "$tmp/core-ok.out" >/dev/null

expect_fail \
  both-core-already-present \
  "refusing to publish: gxfkit-core 1.2.3 is already reserved on Crates.io (state: present); use crate scope 'gxfkit' if only the CLI crate remains" \
  env GXFKIT_FAKE_CRATES_GXFKIT_CORE=present PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 both

expect_fail \
  both-cli-already-yanked \
  "refusing to publish: gxfkit 1.2.3 is already reserved on Crates.io (state: yanked)" \
  env GXFKIT_FAKE_CRATES_GXFKIT=yanked PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 both

expect_fail \
  core-already-present \
  "refusing to publish: gxfkit-core 1.2.3 is already reserved on Crates.io (state: present)" \
  env GXFKIT_FAKE_CRATES_GXFKIT_CORE=present PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit-core

expect_fail \
  cli-missing-core \
  "refusing to publish: gxfkit-core 1.2.3 is not visible on Crates.io; publish gxfkit-core first and wait for registry propagation" \
  env PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit

expect_fail \
  cli-core-yanked \
  "refusing to publish: gxfkit-core 1.2.3 is yanked on Crates.io" \
  env GXFKIT_FAKE_CRATES_GXFKIT_CORE=yanked PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit

expect_fail \
  cli-already-present \
  "refusing to publish: gxfkit 1.2.3 is already reserved on Crates.io (state: present)" \
  env GXFKIT_FAKE_CRATES_GXFKIT_CORE=present GXFKIT_FAKE_CRATES_GXFKIT=present PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit

env GXFKIT_FAKE_CRATES_GXFKIT_CORE=present PATH="$fake_bin:$PATH" \
  bash scripts/check-crates-publish-state.sh 1.2.3 gxfkit \
  >"$tmp/gxfkit-ok.out"
grep -F "verified Crates.io publish state for gxfkit 1.2.3" "$tmp/gxfkit-ok.out" >/dev/null

expect_fail \
  crates-api-error \
  "failed to check Crates.io state for gxfkit-core 1.2.3: HTTP 500" \
  env GXFKIT_FAKE_CRATES_GXFKIT_CORE=error PATH="$fake_bin:$PATH" \
    bash scripts/check-crates-publish-state.sh 1.2.3 both

echo "verified Crates.io publish state tests"
