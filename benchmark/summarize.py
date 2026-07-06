#!/usr/bin/env python3
"""Host-side benchmark assembly.

Reads the artifacts produced inside the container (metrics.tsv + the AGAT/gxfkit
GTF outputs), computes parity with the normalizer, and writes:
  * results/summary.tsv  — machine-readable
  * a markdown table printed to stdout, also injected into README.md between the
    <!-- BENCHMARK_TABLE --> markers.

Usage: summarize.py <results_dir> <normalize.py> [README.md]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

METRICS_HEADER = ["file", "agat_wall_s", "agat_mem_kb", "gxfkit_wall_s", "gxfkit_mem_kb"]
SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def positive_float(raw: str, label: str, name: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise ValueError(f"{name}: invalid {label}: {raw!r}") from exc
    if value <= 0:
        raise ValueError(f"{name}: {label} must be > 0, got {raw!r}")
    return value


def positive_int(raw: str, label: str, name: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"{name}: invalid {label}: {raw!r}") from exc
    if value <= 0:
        raise ValueError(f"{name}: {label} must be > 0, got {raw!r}")
    return value


def parity_rate(normalizer: Path, agat: Path, gxf: Path) -> str:
    """Return parity as a percentage string, or 'OK' if identical."""
    missing = [str(path) for path in (agat, gxf) if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing GTF output(s): {', '.join(missing)}")
    r = subprocess.run(
        [sys.executable, str(normalizer), str(agat), str(gxf)],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        return "100.00"
    for line in r.stderr.splitlines():
        if "parity=" in line:
            return line.split("parity=")[1].strip().rstrip("%")
    raise RuntimeError(
        f"normalizer did not report parity for {agat.name} vs {gxf.name}:\n{r.stderr}"
    )


def fmt_secs(s: float) -> str:
    return f"{s*1000:.0f} ms" if s < 1 else f"{s:.2f} s"


def human_kb(kb: str) -> str:
    try:
        v = int(kb)
    except (ValueError, TypeError):
        return "NA"
    return f"{v/1_048_576:.2f} GB" if v >= 1_048_576 else f"{v/1024:.0f} MB"


def validate_name(name: str, metrics: Path, lineno: int, seen: set[str]) -> bool:
    if not name:
        print(f"{metrics}:{lineno}: empty file name", file=sys.stderr)
        return False
    if not SAFE_NAME_RE.match(name):
        print(
            f"{metrics}:{lineno}: unsafe file name {name!r}; expected [A-Za-z0-9_.-]+",
            file=sys.stderr,
        )
        return False
    if name in seen:
        print(f"{metrics}:{lineno}: duplicate file name {name!r}", file=sys.stderr)
        return False
    seen.add(name)
    return True


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    results = Path(argv[1])
    normalizer = Path(argv[2])
    readme = Path(argv[3]) if len(argv) > 3 else None
    if not normalizer.exists():
        print(f"normalizer not found: {normalizer}", file=sys.stderr)
        return 1
    if readme and not readme.exists():
        print(f"README target not found: {readme}", file=sys.stderr)
        return 1

    rows = []
    metrics = results / "metrics.tsv"
    if not metrics.exists():
        print(f"no metrics at {metrics}", file=sys.stderr)
        return 1
    lines = metrics.read_text().splitlines()
    if not lines:
        print(f"empty metrics at {metrics}", file=sys.stderr)
        return 1
    header = lines[0].split("\t")
    if header != METRICS_HEADER:
        print(
            f"{metrics}: unexpected header {header!r}; expected {METRICS_HEADER!r}",
            file=sys.stderr,
        )
        return 1
    seen_names: set[str] = set()
    for lineno, line in enumerate(lines[1:], start=2):  # skip header
        parts = line.split("\t")
        if len(parts) != 5:
            print(f"{metrics}:{lineno}: expected 5 tab-separated fields", file=sys.stderr)
            return 1
        name, agat_s, agat_mem, gxf_s, gxf_mem = parts
        if not validate_name(name, metrics, lineno, seen_names):
            return 1
        try:
            a = positive_float(agat_s, "AGAT wall time", name)
            g = positive_float(gxf_s, "gxfkit wall time", name)
            positive_int(agat_mem, "AGAT max RSS", name)
            positive_int(gxf_mem, "gxfkit max RSS", name)
        except ValueError as exc:
            print(exc, file=sys.stderr)
            return 1
        try:
            par = parity_rate(
                normalizer, results / f"{name}.agat.gtf", results / f"{name}.gxfkit.gtf"
            )
        except (FileNotFoundError, RuntimeError) as exc:
            print(exc, file=sys.stderr)
            return 1
        speed = f"{a/g:.1f}×"
        rows.append(
            {
                "file": name,
                "agat_s": agat_s,
                "gxf_s": gxf_s,
                "agat_disp": fmt_secs(a),
                "gxf_disp": fmt_secs(g),
                "speed": speed,
                "agat_mem": human_kb(agat_mem),
                "gxf_mem": human_kb(gxf_mem),
                "parity": par,
            }
        )
    if not rows:
        print("no benchmark rows were evaluated", file=sys.stderr)
        return 1

    # machine-readable
    tsv = results / "summary.tsv"
    with tsv.open("w") as fh:
        fh.write("file\tagat_s\tgxfkit_s\tspeedup\tagat_mem\tgxfkit_mem\tparity%\n")
        for r in rows:
            fh.write(
                f"{r['file']}\t{r['agat_s']}\t{r['gxf_s']}\t{r['speed']}\t"
                f"{r['agat_mem']}\t{r['gxf_mem']}\t{r['parity']}\n"
            )

    # markdown
    md = [
        "| file | AGAT | gxfkit | speedup | AGAT mem | gxfkit mem | parity |",
        "|------|------|--------|---------|----------|------------|--------|",
    ]
    for r in rows:
        md.append(
            f"| `{r['file']}` | {r['agat_disp']} | {r['gxf_disp']} | "
            f"**{r['speed']}** | {r['agat_mem']} | {r['gxf_mem']} | {r['parity']}% |"
        )
    table = "\n".join(md)
    print(table)

    if readme and readme.exists():
        text = readme.read_text(encoding="utf-8")
        a, b = "<!-- BENCHMARK_TABLE -->", "<!-- /BENCHMARK_TABLE -->"
        if a not in text or b not in text:
            print(f"{readme}: missing benchmark table markers", file=sys.stderr)
            return 1
        pre = text[: text.index(a) + len(a)]
        post = text[text.index(b):]
        readme.write_text(f"{pre}\n{table}\n{post}", encoding="utf-8")
        print(f"\n[injected table into {readme}]", file=sys.stderr)

    # Optional CI gate: fail if any file's parity drops below MIN_PARITY.
    import os

    floor = os.environ.get("MIN_PARITY")
    if floor:
        try:
            floor = float(floor)
        except ValueError:
            print(f"MIN_PARITY must be a number, got {floor!r}", file=sys.stderr)
            return 1
        # A missing/NA parity means the normalizer crashed or an output file is
        # missing — that's a failure, not a pass-by-omission.
        bad = [r for r in rows if float(r["parity"]) < floor]
        if bad:
            for r in bad:
                why = "no parity computed" if r["parity"] == "NA" else f"{r['parity']}% < {floor}%"
                print(f"PARITY REGRESSION: {r['file']} {why}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
