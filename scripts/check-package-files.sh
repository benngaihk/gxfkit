#!/usr/bin/env bash
# Verify crate packages include required distribution files.
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

allow_dirty="${PACKAGE_FILES_ALLOW_DIRTY:-1}"
if [ "$allow_dirty" != 0 ] && [ "$allow_dirty" != 1 ]; then
  echo "PACKAGE_FILES_ALLOW_DIRTY must be 0 or 1, got: $allow_dirty" >&2
  exit 2
fi

required_files=(
  Cargo.toml
  README.md
  LICENSE
)

required_source_file() {
  case "$1" in
    gxfkit-core)
      printf '%s\n' "src/lib.rs"
      ;;
    gxfkit)
      printf '%s\n' "src/main.rs"
      ;;
    *)
      echo "unknown crate for package file check: $1" >&2
      return 2
      ;;
  esac
}

check_crate() {
  local crate="$1"
  local package_args
  local files
  package_args=(package -p "$crate" --list --locked)
  if [ "$allow_dirty" = 1 ]; then
    package_args+=(--allow-dirty)
  fi
  files="$("$CARGO_BIN" "${package_args[@]}")"
  for required in "${required_files[@]}"; do
    if ! printf '%s\n' "$files" | grep -Fx "$required" >/dev/null; then
      echo "$crate package is missing $required" >&2
      return 1
    fi
  done
  local source_file
  source_file="$(required_source_file "$crate")"
  if ! printf '%s\n' "$files" | grep -Fx "$source_file" >/dev/null; then
    echo "$crate package is missing $source_file" >&2
    return 1
  fi
}

if [ "$#" -eq 0 ]; then
  set -- gxfkit-core gxfkit
fi

for crate in "$@"; do
  check_crate "$crate"
done

echo "verified locked package file lists for $*"
