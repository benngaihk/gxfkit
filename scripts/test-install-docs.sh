#!/usr/bin/env bash
# Regression tests for scripts/check-install-docs.py.
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
  mkdir -p "$dir/docs"
  cat >"$dir/docs/RELEASE-STATUS.md" <<'MD'
# Release Status

## Current public version: `0.0.1`

- Crates.io `gxfkit 0.0.1` is not published.
MD
  cat >"$dir/README.md" <<'MD'
Published `v0.0.1` archives predate the no-overwrite output guard.
The public install audit verifies future releases with no-overwrite.

Once published to Crates.io:

Crates.io is not a current public channel while
docs/RELEASE-STATUS.md records `gxfkit` as unpublished there; do not treat
`cargo install gxfkit` as a production install path until this section stops
being conditional.

```bash
cargo install gxfkit
conda install -c conda-forge -c bioconda gxfkit
```

The current public Bioconda package is `0.0.2` and has passed clean install,
smoke conversion, and no-overwrite verification. Use the release status before
treating all public channels as strict-audit production evidence.
MD
  cat >"$dir/README.zh-CN.md" <<'MD'
已发布的 `v0.0.1` 包早于“拒绝覆盖输出文件”保护。
公开安装审计默认会验证 no-overwrite 和核心语料 parity。

```bash
conda install -c conda-forge -c bioconda gxfkit
```

当前公开的 Bioconda 包是 `0.0.2`，并已通过干净安装、smoke 转换和拒绝覆盖验证；
判断所有公开渠道能否作为严格生产证据前，请以发布状态文档为准。

### 计划中的分发方式

- Crates.io：`cargo install gxfkit`

这些入口在正式发布前不应写进生产文档作为已可用渠道。
MD
}

"$PY" scripts/check-install-docs.py >"$tmp/current.out"
grep -F "verified install docs" "$tmp/current.out" >/dev/null

fixture="$tmp/good"
make_fixture "$fixture"
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py" >"$tmp/good.out"
grep -F "verified install docs" "$tmp/good.out" >/dev/null

fixture="$tmp/missing-cautious-cargo"
make_fixture "$fixture"
perl -0pi -e 's/Once published to Crates\.io:/Crates.io:/' "$fixture/README.md"
expect_fail \
  missing-cautious-cargo \
  "README.md must mention: Once published to Crates.io:" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

fixture="$tmp/missing-crates-current-channel-warning"
make_fixture "$fixture"
perl -0pi -e 's/Crates\.io is not a current public channel while.*?being conditional\.//s' \
  "$fixture/README.md"
expect_fail \
  missing-crates-current-channel-warning \
  "README.md must mention: Crates.io is not a current public channel" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

fixture="$tmp/missing-bioconda-version-boundary"
make_fixture "$fixture"
perl -0pi -e 's/The current public Bioconda package is `0\.0\.2` and has passed clean install,\nsmoke conversion, and no-overwrite verification\.//' \
  "$fixture/README.md"
expect_fail \
  missing-bioconda-version-boundary \
  'README.md must mention: The current public Bioconda package is `0.0.2`' \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

fixture="$tmp/missing-zh-bioconda-boundary"
make_fixture "$fixture"
perl -0pi -e 's/当前公开的 Bioconda 包是 `0\.0\.2`，并已通过干净安装、smoke 转换和拒绝覆盖验证；\n判断所有公开渠道能否作为严格生产证据前，请以发布状态文档为准。//' \
  "$fixture/README.zh-CN.md"
expect_fail \
  missing-zh-bioconda-boundary \
  'README.zh-CN.md must mention: 当前公开的 Bioconda 包是 `0.0.2`' \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

fixture="$tmp/missing-zh-warning"
make_fixture "$fixture"
perl -0pi -e 's/这些入口在正式发布前不应写进生产文档作为已可用渠道。//' \
  "$fixture/README.zh-CN.md"
expect_fail \
  missing-zh-warning \
  "README.zh-CN.md must mention: 这些入口在正式发布前不应写进生产文档作为已可用渠道" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

fixture="$tmp/missing-overwrite-caveat"
make_fixture "$fixture"
perl -0pi -e 's/Published `v0\.0\.1` archives predate the no-overwrite output guard\.//' \
  "$fixture/README.md"
expect_fail \
  missing-overwrite-caveat \
  'README.md must mention: Published `v0.0.1` archives predate the no-overwrite output guard' \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-install-docs.py"

echo "verified install docs tests"
