#!/usr/bin/env bash
# Runs INSIDE the gxfkit-bench container. Pure measurement (no python/parity —
# the AGAT image has no python; those happen host-side in summarize.py).
#
# Two gotchas this script handles, both learned the hard way:
#   1. AGAT REFUSES to overwrite an existing output file — it prints "File X
#      already exist." and exits in ~0.27s without converting. A naive repeated
#      benchmark therefore times AGAT's no-op, not its work. We delete the output
#      file before every timed run. (This is also why we don't use hyperfine: it
#      repeats the same command, so only the first run would be real.)
#   2. AGAT fails fast if CWD is the Docker Desktop bind-mount (it writes a log
#      dir there), so we keep CWD on the container's own filesystem.
#
# Mounts:  /corpus (ro *.gff3)   /work/results (rw outputs)
# Env:     RUNS (timed runs per tool, default 5)
#          BENCH_FILES (optional space-separated basenames, without .gff3)
set -euo pipefail

CORPUS=/corpus
OUT=/work/results
mkdir -p "$OUT"
RUNS="${RUNS:-5}"
BENCH_FILES="${BENCH_FILES:-}"
WORK=/tmp/bench
mkdir -p "$WORK"
cd "$WORK"
METRICS_TMP="$WORK/metrics.tsv"

# Time one real run: remove the output file (AGAT won't overwrite) + its log dir,
# run, emit "<wall_s> <maxRSS_kb>".
time_once() {
  local kind="$1" gff="$2" out="$3"
  rm -f "$out"; rm -rf "$WORK"/agat_log_* 2>/dev/null
  if [ "$kind" = agat ]; then
    if ! /usr/bin/time -f '%e %M' agat_convert_sp_gff2gtf.pl -i "$gff" -o "$out" >/dev/null 2>"$WORK/t.txt"; then
      cat "$WORK/t.txt" >&2
      return 1
    fi
  else
    if ! /usr/bin/time -f '%e %M' gxfkit gff2gtf -i "$gff" -o "$out" >/dev/null 2>"$WORK/t.txt"; then
      cat "$WORK/t.txt" >&2
      return 1
    fi
  fi
  tail -1 "$WORK/t.txt"
}

# Best (min wall) over RUNS cold runs; also tracks the max RSS seen.
time_best() {
  local kind="$1" gff="$2" out="$3" i w m measured best_w="" best_m=0
  for i in $(seq 1 "$RUNS"); do
    measured="$(time_once "$kind" "$gff" "$out")"
    read -r w m <<<"$measured"
    [ -z "$w" ] && continue
    if [ -z "$best_w" ] || awk "BEGIN{exit !($w < $best_w)}"; then best_w="$w"; fi
    if [ "${m:-0}" -gt "$best_m" ]; then best_m="$m"; fi
  done
  echo "${best_w:-NA} ${best_m:-NA}"
}

echo "# gxfkit vs AGAT — gff2gtf  (best of RUNS=$RUNS cold runs)"
echo "# gxfkit: $(gxfkit version)"
: >"$METRICS_TMP"
echo -e "file\tagat_wall_s\tagat_mem_kb\tgxfkit_wall_s\tgxfkit_mem_kb" >>"$METRICS_TMP"

processed=0
for gff in "$CORPUS"/*.gff3; do
  [ -e "$gff" ] || continue
  name=$(basename "$gff" .gff3)
  if [ -n "$BENCH_FILES" ] && [[ " $BENCH_FILES " != *" $name "* ]]; then
    continue
  fi
  echo "=== $name ==="

  # Persisted outputs for host-side parity (delete first: AGAT won't overwrite).
  rm -f "$OUT/${name}.agat.gtf" "$OUT/${name}.gxfkit.gtf"; rm -rf "$WORK"/agat_log_*
  if ! agat_convert_sp_gff2gtf.pl -i "$gff" -o "$OUT/${name}.agat.gtf" >/dev/null 2>"$WORK/agat.persist.err"; then
    cat "$WORK/agat.persist.err" >&2
    exit 1
  fi
  if ! gxfkit gff2gtf -i "$gff" -o "$OUT/${name}.gxfkit.gtf" >/dev/null 2>"$WORK/gxfkit.persist.err"; then
    cat "$WORK/gxfkit.persist.err" >&2
    exit 1
  fi

  read -r aw am < <(time_best agat   "$gff" "$WORK/a.gtf")
  read -r gw gm < <(time_best gxfkit "$gff" "$WORK/g.gtf")
  speed=$(awk "BEGIN{ if ($gw>0) printf \"%.1f\", $aw/$gw; else print \"NA\" }" 2>/dev/null)
  echo "  wall: agat=${aw}s gxfkit=${gw}s  speedup=${speed}x"
  echo "  mem:  agat=${am}KB gxfkit=${gm}KB"
  echo -e "${name}\t${aw}\t${am}\t${gw}\t${gm}" >>"$METRICS_TMP"
  processed=$((processed + 1))
done

if [ "$processed" -eq 0 ]; then
  echo "no corpus files matched BENCH_FILES='${BENCH_FILES}'" >&2
  exit 1
fi

mv "$METRICS_TMP" "$OUT/metrics.tsv"
echo "# done — host summarize.py computes parity + assembles the table"
