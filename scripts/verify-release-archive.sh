#!/usr/bin/env bash
# Verify a packaged gxfkit release archive the way a user would consume it.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 path/to/gxfkit-*.tar.gz" >&2
  exit 2
fi

archive="$1"
run_smoke="${VERIFY_RELEASE_ARCHIVE_SMOKE:-1}"
verify_no_overwrite="${VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE:-1}"
expected_version="${VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION:-}"
case "$run_smoke" in
  0 | 1) ;;
  *)
    echo "VERIFY_RELEASE_ARCHIVE_SMOKE must be 0 or 1, got: $run_smoke" >&2
    exit 2
    ;;
esac
case "$verify_no_overwrite" in
  0 | 1) ;;
  *)
    echo "VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE must be 0 or 1, got: $verify_no_overwrite" >&2
    exit 2
    ;;
esac
if [ -n "$expected_version" ] \
  && ! printf '%s\n' "$expected_version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION must look like X.Y.Z, got: $expected_version" >&2
  exit 2
fi
if [ ! -f "$archive" ]; then
  echo "archive not found: $archive" >&2
  exit 1
fi

archive_dir="$(cd "$(dirname "$archive")" && pwd)"
archive_name="$(basename "$archive")"
case "$archive_name" in
  *.tar.gz) ;;
  *)
    echo "archive must be a .tar.gz file: $archive_name" >&2
    exit 1
    ;;
esac
case "$archive_name" in
  gxfkit-v*.tar.gz) ;;
  *)
    echo "archive name must look like gxfkit-v*.tar.gz, got: $archive_name" >&2
    exit 1
    ;;
esac
archive_root="${archive_name%.tar.gz}"
if [ -n "$expected_version" ]; then
  case "$archive_name" in
    "gxfkit-v${expected_version}-"*.tar.gz) ;;
    *)
      echo "archive name must match expected version $expected_version, got: $archive_name" >&2
      exit 1
      ;;
  esac
fi

if [ ! -f "${archive}.sha256" ]; then
  echo "checksum file not found: ${archive}.sha256" >&2
  exit 1
fi
checksum_lines="$(wc -l <"${archive}.sha256" | tr -d ' ')"
if [ "$checksum_lines" -ne 1 ]; then
  echo "checksum file must contain exactly one line: ${archive}.sha256" >&2
  exit 1
fi
read -r checksum checksum_target <"${archive}.sha256"
if ! printf '%s\n' "$checksum" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "checksum file does not start with a lowercase sha256 digest: ${archive}.sha256" >&2
  exit 1
fi
if [ "$checksum_target" != "$archive_name" ]; then
  echo "checksum file must verify $archive_name, got: ${checksum_target:-<empty>}" >&2
  exit 1
fi
(
  cd "$archive_dir"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "${archive_name}.sha256"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${archive_name}.sha256"
  else
    echo "shasum or sha256sum is required to verify $archive_name" >&2
    exit 127
  fi
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

members="$(tar -tzf "$archive")"
if [ -z "$members" ]; then
  echo "archive is empty: $archive_name" >&2
  exit 1
fi
while IFS= read -r member; do
  case "$member" in
    "$archive_root" | "$archive_root"/*) ;;
    *)
      echo "archive member is outside $archive_root: $member" >&2
      exit 1
      ;;
  esac
  case "$member" in
    /* | ../* | */../* | */..)
      echo "archive member has unsafe path: $member" >&2
      exit 1
      ;;
  esac
  case "$member" in
    "$archive_root" | "$archive_root/" | "$archive_root/gxfkit" | "$archive_root/README.md" | "$archive_root/LICENSE") ;;
    *)
      echo "archive has unexpected member: $member" >&2
      exit 1
      ;;
  esac
done <<<"$members"

python3 - "$archive" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as tar:
    seen = set()
    for member in tar.getmembers():
        if member.name in seen:
            raise SystemExit(f"archive has duplicate member: {member.name}")
        seen.add(member.name)
        if member.issym() or member.islnk():
            raise SystemExit(f"archive member must not be a link: {member.name}")
        if not (member.isdir() or member.isfile()):
            raise SystemExit(
                f"archive member has unsupported type: {member.name}"
            )
PY

tar -xzf "$archive" -C "$tmp"
top_count="$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
if [ "$top_count" -ne 1 ]; then
  echo "archive must contain exactly one top-level directory, found $top_count" >&2
  exit 1
fi
root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit)"
if [ -z "$root" ] || [ "$(basename "$root")" != "$archive_root" ]; then
  echo "archive top-level directory must be $archive_root" >&2
  exit 1
fi

for required in README.md LICENSE; do
  if [ ! -f "$root/$required" ]; then
    echo "archive missing $required" >&2
    exit 1
  fi
done

bin="$root/gxfkit"
if [ ! -f "$bin" ]; then
  echo "archive does not contain a gxfkit binary" >&2
  exit 1
fi
if [ ! -x "$bin" ]; then
  echo "archive gxfkit binary is not executable: $bin" >&2
  exit 1
fi

if [ "$run_smoke" = 0 ]; then
  echo "verified $archive_name (structure only)"
  exit 0
fi

version="$("$bin" version)"
case "$version" in
  "gxfkit "*) ;;
  *)
    echo "unexpected version output: $version" >&2
    exit 1
    ;;
esac
if [ -n "$expected_version" ] && [ "$version" != "gxfkit $expected_version" ]; then
  echo "archive gxfkit version mismatch: expected gxfkit $expected_version, got: $version" >&2
  exit 1
fi
echo "$version"
cat >"$tmp/smoke.gff3" <<'GFF'
##gff-version 3
chr1	src	gene	1	100	.	+	.	ID=gene:g1
chr1	src	mRNA	1	100	.	+	.	ID=transcript:t1;Parent=gene:g1
chr1	src	exon	1	50	.	+	.	Parent=transcript:t1;exon_id=e1
GFF
"$bin" gff2gtf -g "$tmp/smoke.gff3" -o "$tmp/smoke.gtf"
grep 'gene_id "g1"; transcript_id "t1";' "$tmp/smoke.gtf" >/dev/null
if [ "$verify_no_overwrite" = 1 ]; then
  if "$bin" gff2gtf -g "$tmp/smoke.gff3" -o "$tmp/smoke.gtf" 2>"$tmp/overwrite.err"; then
    echo "gxfkit unexpectedly overwrote smoke.gtf" >&2
    exit 1
  fi
  grep 'refusing to overwrite' "$tmp/overwrite.err" >/dev/null
fi

echo "verified $archive_name"
