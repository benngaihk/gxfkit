#!/usr/bin/env bash
# Regression tests for scripts/verify-crates-install.sh dry-run behavior.
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

VERIFY_CRATES_INSTALL_DRY_RUN=1 VERSION=1.2.3 \
  CARGO=/tmp/fake-cargo \
  bash scripts/verify-crates-install.sh >"$tmp/dry-run.out"
grep -F "version=1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "install --locked --root ROOT --version 1.2.3 --registry crates-io gxfkit" \
  "$tmp/dry-run.out" >/dev/null

fake_cargo="$tmp/fake-cargo"
cat >"$fake_cargo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" != install ]; then
  echo "unexpected cargo command: $*" >&2
  exit 1
fi
shift
root=""
version=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      root="$1"
      ;;
    --version)
      shift
      version="$1"
      ;;
  esac
  shift
done
if [ -z "$root" ] || [ -z "$version" ]; then
  echo "missing fake cargo --root or --version" >&2
  exit 1
fi
mkdir -p "$root/bin"
cat >"$root/bin/gxfkit" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = version ]; then
  echo "gxfkit $version"
  exit 0
fi
if [ "\${1:-}" = gff2gtf ]; then
  out=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      -o|--output)
        shift
        out="\$1"
        ;;
    esac
    shift
  done
  if [ -z "\$out" ]; then
    echo "missing output" >&2
    exit 2
  fi
  if [ -e "\$out" ]; then
    echo "refusing to overwrite \$out" >&2
    exit 1
  fi
  echo 'chr1	src	exon	1	50	.	+	.	gene_id "g1"; transcript_id "t1";' >"\$out"
  exit 0
fi
echo "unexpected gxfkit command: \$*" >&2
exit 2
EOF
chmod +x "$root/bin/gxfkit"
SH
chmod +x "$fake_cargo"

CARGO="$fake_cargo" VERSION=1.2.3 bash scripts/verify-crates-install.sh \
  >"$tmp/fake-install.out"
grep -F "gxfkit 1.2.3" "$tmp/fake-install.out" >/dev/null
grep -F "verified Crates.io install for gxfkit 1.2.3" "$tmp/fake-install.out" >/dev/null

expect_fail \
  bad-dry-run \
  "VERIFY_CRATES_INSTALL_DRY_RUN must be 0 or 1" \
  env VERIFY_CRATES_INSTALL_DRY_RUN=maybe VERSION=1.2.3 \
    bash scripts/verify-crates-install.sh

expect_fail \
  bad-version \
  "VERSION must look like X.Y.Z" \
  env VERIFY_CRATES_INSTALL_DRY_RUN=1 VERSION=nope \
    bash scripts/verify-crates-install.sh

echo "verified Crates.io install verifier tests"
