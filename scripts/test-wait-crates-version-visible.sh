#!/usr/bin/env bash
# Regression tests for scripts/wait-crates-version-visible.sh.
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
  */crates/gxfkit-core/* | */crates/gxfkit/*) ;;
  *)
    echo "unexpected curl URL: $url" >&2
    exit 2
    ;;
esac
state="${GXFKIT_FAKE_CRATES_STATE:-present}"
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
    bash scripts/wait-crates-version-visible.sh nope gxfkit

expect_fail \
  bad-crate \
  "crate must be one of: gxfkit-core, gxfkit; got: bad" \
  env PATH="$fake_bin:$PATH" \
    bash scripts/wait-crates-version-visible.sh 1.2.3 bad

expect_fail \
  bad-attempts \
  "GXFKIT_CRATES_IO_WAIT_ATTEMPTS must be a positive integer, got: 0" \
  env GXFKIT_CRATES_IO_WAIT_ATTEMPTS=0 PATH="$fake_bin:$PATH" \
    bash scripts/wait-crates-version-visible.sh 1.2.3 gxfkit

env PATH="$fake_bin:$PATH" \
  bash scripts/wait-crates-version-visible.sh 1.2.3 gxfkit-core \
  >"$tmp/present.out"
grep -F "verified Crates.io visibility for gxfkit-core 1.2.3" "$tmp/present.out" >/dev/null

expect_fail \
  yanked \
  "gxfkit 1.2.3 is visible on Crates.io but yanked" \
  env GXFKIT_FAKE_CRATES_STATE=yanked PATH="$fake_bin:$PATH" \
    bash scripts/wait-crates-version-visible.sh 1.2.3 gxfkit

expect_fail \
  timeout \
  "Timed out waiting for gxfkit 1.2.3 on Crates.io." \
  env \
    GXFKIT_FAKE_CRATES_STATE=absent \
    GXFKIT_CRATES_IO_WAIT_ATTEMPTS=2 \
    GXFKIT_CRATES_IO_WAIT_INTERVAL=1 \
    PATH="$fake_bin:$PATH" \
    bash scripts/wait-crates-version-visible.sh 1.2.3 gxfkit

expect_fail \
  api-error \
  "failed to check Crates.io visibility for gxfkit 1.2.3: HTTP 500" \
  env GXFKIT_FAKE_CRATES_STATE=error PATH="$fake_bin:$PATH" \
    bash scripts/wait-crates-version-visible.sh 1.2.3 gxfkit

echo "verified Crates.io visibility wait tests"
