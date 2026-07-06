#!/usr/bin/env bash
# Prevent publishing a crate version from a different commit than an existing tag.
set -euo pipefail

ROOT="${GXFKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python >/dev/null 2>&1; then
    PY=python
  else
    PY=python3
  fi
fi

version="${VERSION:-}"
if [ -z "$version" ]; then
  version="$("$PY" - <<'PY'
from pathlib import Path
import re

text = Path("Cargo.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version = "([^"]+)"$', text)
if not match:
    raise SystemExit("missing workspace version")
print(match.group(1))
PY
)"
fi
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERSION must look like X.Y.Z, got: $version" >&2
  exit 2
fi
tag="v$version"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  head="$(git rev-parse HEAD)"
  tagged="$(git rev-parse "refs/tags/$tag^{commit}")"
  if [ "$head" != "$tagged" ]; then
    cat >&2 <<MSG
Refusing to publish version $version from a commit different from tag $tag.

Publishing the same version from a different commit would make public channels
disagree. Check out $tag or bump the workspace version before publishing.
MSG
    exit 1
  fi
  echo "publish ref OK: HEAD matches $tag"
else
  echo "publish ref OK: tag $tag does not exist yet"
fi
