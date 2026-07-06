#!/usr/bin/env bash
# Regression tests for scripts/check-crate-metadata.py.
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

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/crates/gxfkit-core/src" "$dir/crates/gxfkit/src"
  cat >"$dir/Cargo.toml" <<'TOML'
[workspace]
resolver = "2"
members = ["crates/gxfkit-core", "crates/gxfkit"]

[workspace.package]
version = "1.2.3"
edition = "2021"
license = "MIT"
repository = "https://github.com/benngaihk/gxfkit"
homepage = "https://github.com/benngaihk/gxfkit"
authors = ["gxfkit contributors"]
keywords = ["bioinformatics", "gff", "gtf", "genomics", "agat"]
categories = ["command-line-utilities", "science"]
TOML

  cat >"$dir/crates/gxfkit-core/Cargo.toml" <<'TOML'
[package]
name = "gxfkit-core"
version.workspace = true
edition.workspace = true
license.workspace = true
description = "Core GFF/GTF model, parsing, and conversions for gxfkit"
repository.workspace = true
homepage.workspace = true
documentation = "https://docs.rs/gxfkit-core"
keywords.workspace = true
categories.workspace = true
readme = "README.md"
TOML

  cat >"$dir/crates/gxfkit/Cargo.toml" <<'TOML'
[package]
name = "gxfkit"
version.workspace = true
edition.workspace = true
license.workspace = true
description = "A fast, AGAT-compatible Rust implementation of common GTF/GFF operations"
repository.workspace = true
homepage.workspace = true
documentation = "https://docs.rs/gxfkit"
keywords.workspace = true
categories.workspace = true
readme = "README.md"

[[bin]]
name = "gxfkit"
path = "src/main.rs"

[dependencies]
gxfkit-core = { version = "1.2.3", path = "../gxfkit-core" }
TOML

  printf '# gxfkit-core\n' >"$dir/crates/gxfkit-core/README.md"
  printf '# gxfkit\n' >"$dir/crates/gxfkit/README.md"
  printf 'MIT\n' >"$dir/crates/gxfkit-core/LICENSE"
  printf 'MIT\n' >"$dir/crates/gxfkit/LICENSE"
}

"$PY" scripts/check-crate-metadata.py >"$tmp/current.out"
grep -F "verified crates.io metadata" "$tmp/current.out" >/dev/null

fixture="$tmp/good"
make_fixture "$fixture"
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-crate-metadata.py" >"$tmp/good.out"
grep -F "verified crates.io metadata" "$tmp/good.out" >/dev/null

fixture="$tmp/bad-docs"
make_fixture "$fixture"
perl -0pi -e 's#documentation = "https://docs.rs/gxfkit"#documentation = "https://example.invalid/gxfkit"#' \
  "$fixture/crates/gxfkit/Cargo.toml"
expect_fail \
  bad-docs \
  "package documentation must be https://docs.rs/gxfkit" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-crate-metadata.py"

fixture="$tmp/bad-keywords"
make_fixture "$fixture"
perl -0pi -e 's/keywords = \["bioinformatics", "gff", "gtf", "genomics", "agat"\]/keywords = ["bioinformatics", "gff", "gtf", "genomics", "agat", "extra"]/' \
  "$fixture/Cargo.toml"
expect_fail \
  bad-keywords \
  "workspace package keywords must contain 1 to 5 entries" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-crate-metadata.py"

fixture="$tmp/bad-dep-version"
make_fixture "$fixture"
perl -0pi -e 's/gxfkit-core = \{ version = "1\.2\.3"/gxfkit-core = { version = "1.2.2"/' \
  "$fixture/crates/gxfkit/Cargo.toml"
expect_fail \
  bad-dep-version \
  "gxfkit-core dependency version must match workspace version 1.2.3" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-crate-metadata.py"

fixture="$tmp/bad-readme"
make_fixture "$fixture"
rm "$fixture/crates/gxfkit-core/README.md"
expect_fail \
  bad-readme \
  "package readme file must exist" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-crate-metadata.py"

echo "verified crates.io metadata tests"
