#!/usr/bin/env bash
# Regression tests for scripts/verify-local-cargo-install.sh.
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

fake_cargo="$tmp/fake-cargo"
cat >"$fake_cargo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

expect_offline="${EXPECT_OFFLINE:-0}"
offline=0
root=""
prev=""
for arg in "$@"; do
  if [ "$arg" = "--offline" ]; then
    offline=1
  fi
  if [ "$prev" = "--root" ]; then
    root="$arg"
  fi
  prev="$arg"
done
test "$1" = install
case " $* " in
  *" --locked "*) ;;
  *) echo "missing --locked" >&2; exit 1 ;;
esac
case " $* " in
  *" --no-track "*) ;;
  *) echo "missing --no-track" >&2; exit 1 ;;
esac
case " $* " in
  *" --path crates/gxfkit "*) ;;
  *) echo "missing local path" >&2; exit 1 ;;
esac
if [ "$offline" != "$expect_offline" ]; then
  echo "offline=$offline expected=$expect_offline" >&2
  exit 1
fi
if [ -z "$root" ]; then
  echo "missing --root value" >&2
  exit 1
fi
mkdir -p "$root/bin"
cat >"$root/bin/gxfkit" <<'BIN'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = version ]; then
  echo "gxfkit test"
  exit 0
fi
if [ "${1:-}" = gff2gtf ]; then
  out=""
  prev=""
  for arg in "$@"; do
    if [ "$prev" = "-o" ]; then
      out="$arg"
    fi
    prev="$arg"
  done
  test -n "$out"
  echo 'chr1	src	exon	1	50	.	+	.	gene_id "g1"; transcript_id "t1";' >"$out"
  exit 0
fi
echo "unexpected gxfkit args: $*" >&2
exit 1
BIN
chmod +x "$root/bin/gxfkit"
SH
chmod +x "$fake_cargo"

EXPECT_OFFLINE=0 CARGO="$fake_cargo" \
  bash scripts/verify-local-cargo-install.sh >"$tmp/network.out"
grep -F "verified local cargo install" "$tmp/network.out" >/dev/null

EXPECT_OFFLINE=1 VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="$fake_cargo" \
  bash scripts/verify-local-cargo-install.sh >"$tmp/offline.out"
grep -F "verified local cargo install" "$tmp/offline.out" >/dev/null

expect_fail \
  invalid-network-setting \
  "VERIFY_LOCAL_CARGO_INSTALL_NETWORK must be 0 or 1, got: maybe" \
  env VERIFY_LOCAL_CARGO_INSTALL_NETWORK=maybe CARGO="$fake_cargo" \
    bash scripts/verify-local-cargo-install.sh

echo "verified local cargo install verifier tests"
