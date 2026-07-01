#!/usr/bin/env bash
# Local preflight before cutting a gxfkit release tag.
#
# This intentionally checks the cheap, deterministic pieces locally. The
# cross-platform archives are still validated by .github/workflows/release.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CARGO_BIN="${CARGO:-cargo}"
if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
  else
    echo "cargo not found on PATH and $HOME/.cargo/bin/cargo is missing" >&2
    exit 127
  fi
fi

echo ">> formatting"
"$CARGO_BIN" fmt --all -- --check

echo ">> linting"
"$CARGO_BIN" clippy --all-targets -- -D warnings

echo ">> tests"
"$CARGO_BIN" test --all

echo ">> release build"
"$CARGO_BIN" build --release --locked --bin gxfkit

echo ">> package gxfkit-core"
"$CARGO_BIN" package -p gxfkit-core --locked --allow-dirty

echo ">> package gxfkit"
if "$CARGO_BIN" package -p gxfkit --locked --allow-dirty; then
  echo "gxfkit package verification passed"
else
  cat >&2 <<'MSG'
gxfkit package verification did not complete.

This is expected before gxfkit-core has been published to the registry, because
the binary crate depends on gxfkit-core by version. Publish order is:
  1. cargo publish -p gxfkit-core
  2. wait for the registry index to update
  3. cargo publish -p gxfkit
MSG
fi

echo ">> release preflight complete"
