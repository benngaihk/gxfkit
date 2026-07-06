#!/usr/bin/env bash
# Regression tests for scripts/check-package-files.sh.
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

fake_cargo="$tmp/cargo-ok"
cat >"$fake_cargo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = package
test "$2" = -p
test "$4" = --list
test "$5" = --locked
test "$6" = --allow-dirty
case "$3" in
  gxfkit-core)
    printf 'Cargo.toml\nREADME.md\nLICENSE\nsrc/lib.rs\n'
    ;;
  gxfkit)
    printf 'Cargo.toml\nREADME.md\nLICENSE\nsrc/main.rs\n'
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$fake_cargo"

CARGO="$fake_cargo" bash scripts/check-package-files.sh >"$tmp/ok.out"
grep -F "verified locked package file lists for gxfkit-core gxfkit" "$tmp/ok.out" >/dev/null

fake_strict="$tmp/cargo-strict"
cat >"$fake_strict" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = package
test "$2" = -p
test "$4" = --list
test "$5" = --locked
test "$#" -eq 5
case "$3" in
  gxfkit-core)
    printf 'Cargo.toml\nREADME.md\nLICENSE\nsrc/lib.rs\n'
    ;;
  gxfkit)
    printf 'Cargo.toml\nREADME.md\nLICENSE\nsrc/main.rs\n'
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$fake_strict"

PACKAGE_FILES_ALLOW_DIRTY=0 CARGO="$fake_strict" \
  bash scripts/check-package-files.sh >"$tmp/strict.out"
grep -F "verified locked package file lists for gxfkit-core gxfkit" "$tmp/strict.out" >/dev/null

expect_fail \
  invalid-dirty-setting \
  "PACKAGE_FILES_ALLOW_DIRTY must be 0 or 1, got: maybe" \
  env PACKAGE_FILES_ALLOW_DIRTY=maybe CARGO="$fake_cargo" bash scripts/check-package-files.sh

fake_missing="$tmp/cargo-missing"
cat >"$fake_missing" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'Cargo.toml\nREADME.md\nsrc/lib.rs\n'
SH
chmod +x "$fake_missing"

expect_fail \
  missing-license \
  "gxfkit-core package is missing LICENSE" \
  env CARGO="$fake_missing" bash scripts/check-package-files.sh

fake_missing_readme="$tmp/cargo-missing-readme"
cat >"$fake_missing_readme" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'Cargo.toml\nLICENSE\nsrc/lib.rs\n'
SH
chmod +x "$fake_missing_readme"

expect_fail \
  missing-readme \
  "gxfkit package is missing README.md" \
  env CARGO="$fake_missing_readme" bash scripts/check-package-files.sh gxfkit

fake_missing_source="$tmp/cargo-missing-source"
cat >"$fake_missing_source" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'Cargo.toml\nREADME.md\nLICENSE\nsrc/lib.rs\n'
SH
chmod +x "$fake_missing_source"

expect_fail \
  missing-binary-source \
  "gxfkit package is missing src/main.rs" \
  env CARGO="$fake_missing_source" bash scripts/check-package-files.sh gxfkit

echo "verified package file list tests"
