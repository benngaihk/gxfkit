#!/usr/bin/env bash
# Emit a pasteable Markdown release evidence report.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_PUBLIC=0
RUN_PUBLIC_AUDIT=0
ALLOW_DIRTY=0
PUBLIC_AUDIT_LOG=""
RELEASE_CHECK_LOG=""
PUBLIC_AUDIT_CHANNELS="github-linux github-parity bioconda crates"
PUBLIC_AUDIT_ALLOW_MISSING_CRATES=0
PUBLIC_AUDIT_NO_OVERWRITE=1
PUBLIC_AUDIT_MIN_PARITY=100
PUBLIC_AUDIT_BENCH_FILES="human_chr1 human_chr21 yeast"
PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT="scripts/verify-crates-install.sh"
FAILED_BLOCKS=()

usage() {
  cat <<'USAGE'
usage: scripts/release-evidence.sh [--check-public] [--run-public-audit] [--allow-dirty] [--release-check-log PATH] [--public-audit-log PATH] [--public-audit-channels CHANNELS] [--public-audit-allow-missing-crates 0|1] [--public-audit-no-overwrite 0|1] [--public-audit-min-parity N] [--public-audit-bench-files FILES] [--public-audit-crates-install-script PATH]

By default this is non-destructive, local, and mostly offline. It records the
release candidate state plus the strict public audit dry-run. Use --check-public
after publishing to query GitHub/Bioconda/Crates.io. Use --run-public-audit only
for the final strict install audit. Set VERSION=X.Y.Z and RELEASE_TAG=vX.Y.Z to
generate evidence for an explicit public release instead of the checkout version.
Use --public-audit-log PATH to append the captured output from an audit that
was already run by the caller. By default that recorded-log guard expects the
final strict public-audit settings.
Use --release-check-log PATH to append and validate a captured
RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh transcript with
a trailing release-check-exit-code=0 line.
When --public-audit-log is provided, the public-audit-* options validate that
recorded log against the same settings used by the caller. The final strict
closure command remains unchanged and requires all public channels to pass.
USAGE
}

validate_version() {
  local value="$1"
  if ! printf '%s\n' "$value" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
    echo "VERSION must look like X.Y.Z, got: $value" >&2
    exit 2
  fi
}

validate_public_audit_channels() {
  local channel
  local count=0
  local seen=" "
  set -f
  for channel in $PUBLIC_AUDIT_CHANNELS; do
    count=$((count + 1))
    case "$channel" in
      github-linux | github-parity | bioconda | crates) ;;
      *)
        echo "--public-audit-channels contains unknown channel: $channel" >&2
        exit 2
        ;;
    esac
    case "$seen" in
      *" $channel "*)
        echo "--public-audit-channels must not repeat: $channel" >&2
        exit 2
        ;;
    esac
    seen="${seen}${channel} "
  done
  set +f
  if [ "$count" -eq 0 ]; then
    echo "--public-audit-channels must include at least one channel" >&2
    exit 2
  fi
}

validate_public_audit_bench_files() {
  local item
  local count=0
  local seen=" "
  set -f
  for item in $PUBLIC_AUDIT_BENCH_FILES; do
    count=$((count + 1))
    case "$item" in
      *[!A-Za-z0-9._-]* | . | ..)
        echo "--public-audit-bench-files entries must be corpus basenames, got: $item" >&2
        exit 2
        ;;
    esac
    case "$seen" in
      *" $item "*)
        echo "--public-audit-bench-files must not repeat: $item" >&2
        exit 2
        ;;
    esac
    seen="${seen}${item} "
  done
  set +f
  if [ "$count" -eq 0 ]; then
    echo "--public-audit-bench-files must include at least one corpus name" >&2
    exit 2
  fi
}

validate_public_audit_min_parity() {
  python3 - "$PUBLIC_AUDIT_MIN_PARITY" <<'PY'
import sys

value = sys.argv[1]
try:
    parsed = float(value)
except ValueError:
    raise SystemExit(f"--public-audit-min-parity must be a number, got: {value}")
if not 0 <= parsed <= 100:
    raise SystemExit(f"--public-audit-min-parity must be between 0 and 100, got: {value}")
PY
}

validate_public_audit_crates_install_script() {
  case "$PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT" in
    "" | *[[:space:]]*)
      echo "--public-audit-crates-install-script must be a non-empty repository-relative scripts/*.sh path without whitespace, got: $PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT" >&2
      exit 2
      ;;
    /* | -* | *"/../"* | ../* | */.. | ..)
      echo "--public-audit-crates-install-script must be a repository-relative scripts/*.sh path, got: $PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT" >&2
      exit 2
      ;;
    scripts/*.sh) ;;
    *)
      echo "--public-audit-crates-install-script must be a repository-relative scripts/*.sh path, got: $PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT" >&2
      exit 2
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-public)
      CHECK_PUBLIC=1
      ;;
    --run-public-audit)
      CHECK_PUBLIC=1
      RUN_PUBLIC_AUDIT=1
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      ;;
    --public-audit-log)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-log requires a path" >&2
        exit 2
      fi
      PUBLIC_AUDIT_LOG="$1"
      ;;
    --public-audit-channels)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-channels requires a value" >&2
        exit 2
      fi
      PUBLIC_AUDIT_CHANNELS="$1"
      ;;
    --public-audit-allow-missing-crates)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-allow-missing-crates requires 0 or 1" >&2
        exit 2
      fi
      PUBLIC_AUDIT_ALLOW_MISSING_CRATES="$1"
      ;;
    --public-audit-no-overwrite)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-no-overwrite requires 0 or 1" >&2
        exit 2
      fi
      PUBLIC_AUDIT_NO_OVERWRITE="$1"
      ;;
    --public-audit-min-parity)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-min-parity requires a value" >&2
        exit 2
      fi
      PUBLIC_AUDIT_MIN_PARITY="$1"
      ;;
    --public-audit-bench-files)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-bench-files requires a value" >&2
        exit 2
      fi
      PUBLIC_AUDIT_BENCH_FILES="$1"
      ;;
    --public-audit-crates-install-script)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--public-audit-crates-install-script requires a value" >&2
        exit 2
      fi
      PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT="$1"
      ;;
    --release-check-log)
      shift
      if [ "$#" -eq 0 ]; then
        usage >&2
        echo "--release-check-log requires a path" >&2
        exit 2
      fi
      RELEASE_CHECK_LOG="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

workspace_version="$(python3 - <<'PY'
from pathlib import Path
import re

text = Path("Cargo.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version = "([^"]+)"$', text)
if not match:
    raise SystemExit("missing workspace version")
print(match.group(1))
PY
)"
version="${VERSION:-$workspace_version}"
tag="${RELEASE_TAG:-v$version}"
validate_version "$version"
case "$tag" in
  v*) ;;
  *)
    echo "RELEASE_TAG must start with v, got: $tag" >&2
    exit 2
    ;;
esac
validate_version "${tag#v}"
if [ "${tag#v}" != "$version" ]; then
  echo "VERSION and RELEASE_TAG disagree: VERSION=$version RELEASE_TAG=$tag" >&2
  exit 2
fi
case "$PUBLIC_AUDIT_ALLOW_MISSING_CRATES" in
  0 | 1) ;;
  *)
    echo "--public-audit-allow-missing-crates must be 0 or 1, got: $PUBLIC_AUDIT_ALLOW_MISSING_CRATES" >&2
    exit 2
    ;;
esac
case "$PUBLIC_AUDIT_NO_OVERWRITE" in
  0 | 1) ;;
  *)
    echo "--public-audit-no-overwrite must be 0 or 1, got: $PUBLIC_AUDIT_NO_OVERWRITE" >&2
    exit 2
    ;;
esac
validate_public_audit_channels
if [ "$PUBLIC_AUDIT_ALLOW_MISSING_CRATES" = 1 ]; then
  case " $PUBLIC_AUDIT_CHANNELS " in
    *" crates "*) ;;
    *)
      echo "--public-audit-allow-missing-crates=1 requires the crates channel" >&2
      exit 2
      ;;
  esac
fi
validate_public_audit_min_parity
validate_public_audit_bench_files
validate_public_audit_crates_install_script
commit="$(git rev-parse HEAD 2>/dev/null || printf '<unknown>')"
dirty_count="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

run_block() {
  local title="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  local rc=$?
  set -e
  printf '## %s\n\n' "$title"
  printf 'Command: `%q' "$1"
  shift
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '`\n\n'
  printf 'Exit: `%s`\n\n' "$rc"
  printf '```text\n'
  cat "$tmp"
  printf '```\n\n'
  rm -f "$tmp"
  if [ "$rc" -ne 0 ]; then
    FAILED_BLOCKS+=("$title=$rc")
  fi
}

emit_local_benchmark_summary() {
  local summary="${RELEASE_EVIDENCE_BENCHMARK_SUMMARY:-benchmark/results/summary.tsv}"
  local tmp
  tmp="$(mktemp)"
  set +e
  python3 scripts/check-benchmark-summary.py "$summary" >"$tmp" 2>&1
  local rc=$?
  set -e
  printf '## Local Benchmark Summary\n\n'
  printf 'Command: `python3 scripts/check-benchmark-summary.py %q`\n\n' "$summary"
  printf 'Exit: `%s`\n\n' "$rc"
  printf 'Validation:\n\n'
  printf '```text\n'
  cat "$tmp"
  printf '```\n\n'
  rm -f "$tmp"
  if [ "$rc" -ne 0 ]; then
    FAILED_BLOCKS+=("Local Benchmark Summary=$rc")
  fi
  if [ ! -f "$summary" ]; then
    printf 'Generate it with:\n\n'
    printf '```bash\n'
    printf 'RUNS=1 BENCH_FILES="human_chr1 human_chr21 yeast" README_OUT= bash benchmark/run.sh\n'
    printf '```\n\n'
    return
  fi

  printf 'Source: `%s`\n\n' "$summary"
  printf '```tsv\n'
  cat "$summary"
  printf '```\n\n'
}

tag_args=(python3 scripts/release-readiness.py --phase tag --version "$version")
public_args=(python3 scripts/release-readiness.py --phase public --version "$version")
if [ "$ALLOW_DIRTY" = 1 ]; then
  tag_args+=(--allow-dirty)
  public_args+=(--allow-dirty)
fi
if [ "$CHECK_PUBLIC" = 1 ]; then
  public_args+=(--check-public)
fi
if [ "$RUN_PUBLIC_AUDIT" = 1 ]; then
  public_args+=(--run-public-audit)
fi

cat <<MD
# gxfkit Release Evidence

- Generated: \`$generated_at\`
- Checkout workspace version: \`$workspace_version\`
- Target release version: \`$version\`
- Release tag: \`$tag\`
- Commit: \`$commit\`
- Dirty worktree entries: \`$dirty_count\`

MD

run_block "Tag Readiness" "${tag_args[@]}"
run_block "Maintainer Surface Guards" python3 scripts/check-maintainer-surfaces.py
run_block "Workflow Policy Guards" python3 scripts/check-workflow-policy.py
run_block "Release Artifact Guards" python3 scripts/check-release-artifacts.py
run_block "Crates.io Metadata Guards" python3 scripts/check-crate-metadata.py
run_block "Package File List Guards" bash scripts/check-package-files.sh
run_block "Bioconda Recipe Guards" python3 scripts/check-bioconda-recipe.py
emit_local_benchmark_summary
run_block "Release Status Doc Guards" python3 scripts/check-release-status-doc.py
run_block "Install Documentation Guards" python3 scripts/check-install-docs.py
run_block "Release Guide Guards" python3 scripts/check-release-doc.py
run_block "Release-Check Contract Guards" python3 scripts/check-release-check.py
if [ -n "$RELEASE_CHECK_LOG" ]; then
  run_block "Recorded Release-Check Log Guards" \
    python3 scripts/check-release-check-log.py --version "$version" "$RELEASE_CHECK_LOG"
  cat <<MD
## Recorded Release-Check Output

Command: \`set +e; RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh > release-check.log 2>&1; rc=\$?; printf 'release-check-exit-code=%s\n' "\$rc" >> release-check.log; exit "\$rc"\`

\`\`\`text
MD
  if [ -f "$RELEASE_CHECK_LOG" ]; then
    cat "$RELEASE_CHECK_LOG"
  else
    printf 'release-check log not found: %s\n' "$RELEASE_CHECK_LOG"
  fi
  cat <<'MD'
```

MD
fi
run_block "Public Readiness" "${public_args[@]}"
run_block "Strict Public Audit Dry Run" \
  env \
    VERIFY_PUBLIC_INSTALLS_DRY_RUN=1 \
    VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
    VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
    VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
    VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
    BENCH_FILES="human_chr1 human_chr21 yeast" \
    VERSION="$version" \
    RELEASE_TAG="$tag" \
  bash scripts/verify-public-installs.sh

if [ -n "$PUBLIC_AUDIT_LOG" ]; then
  recorded_audit_args=(
    python3 scripts/check-public-audit-log.py
    --version "$version"
    --tag "$tag"
    --channels "$PUBLIC_AUDIT_CHANNELS"
    --verify-no-overwrite "$PUBLIC_AUDIT_NO_OVERWRITE"
    --min-parity "$PUBLIC_AUDIT_MIN_PARITY"
    --bench-files "$PUBLIC_AUDIT_BENCH_FILES"
    --crates-install-script "$PUBLIC_AUDIT_CRATES_INSTALL_SCRIPT"
  )
  if [ "$PUBLIC_AUDIT_ALLOW_MISSING_CRATES" = 1 ]; then
    recorded_audit_args+=(--allow-missing-crates)
  fi
  recorded_audit_args+=("$PUBLIC_AUDIT_LOG")

  run_block "Recorded Public Audit Log Guards" "${recorded_audit_args[@]}"

  run_block "Final Strict Public Audit Log Guards" \
    python3 scripts/check-public-audit-log.py \
      --version "$version" \
      --tag "$tag" \
      --channels "github-linux github-parity bioconda crates" \
      --verify-no-overwrite 1 \
      --min-parity 100 \
      --bench-files "human_chr1 human_chr21 yeast" \
      --crates-install-script "scripts/verify-crates-install.sh" \
      "$PUBLIC_AUDIT_LOG"
  cat <<MD
## Strict Public Audit Recorded Output

Command: \`VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 BENCH_FILES="human_chr1 human_chr21 yeast" VERSION=$version RELEASE_TAG=$tag bash scripts/verify-public-installs.sh\`

\`\`\`text
MD
  if [ -f "$PUBLIC_AUDIT_LOG" ]; then
    cat "$PUBLIC_AUDIT_LOG"
  else
    printf 'public audit log not found: %s\n' "$PUBLIC_AUDIT_LOG"
  fi
  cat <<'MD'
```

MD
fi

cat <<MD
## Evidence Status

MD
if [ "${#FAILED_BLOCKS[@]}" -eq 0 ]; then
  cat <<'MD'
All evidence blocks exited with `0`.

MD
else
  cat <<'MD'
One or more evidence blocks exited non-zero. Keep the report, but do not treat
this release as closed until these blocks pass:

MD
  for item in "${FAILED_BLOCKS[@]}"; do
    title="${item%=*}"
    rc="${item##*=}"
    printf -- '- `%s` exited `%s`\n' "$title" "$rc"
  done
  printf '\n'
fi

cat <<MD
## Final Closure Command

\`\`\`bash
python3 scripts/release-readiness.py --phase public --version $version --check-public --run-public-audit

VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \\
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \\
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \\
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \\
BENCH_FILES="human_chr1 human_chr21 yeast" \\
VERSION=$version RELEASE_TAG=$tag bash scripts/verify-public-installs.sh
\`\`\`
MD
