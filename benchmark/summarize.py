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

import subprocess
import sys
from pathlib import Path


def parity_rate(normalizer: Path, agat: Path, gxf: Path) -> str:
    """Return parity as a percentage string, or 'OK' if identical."""
    r = subprocess.run(
        [sys.executable, str(normalizer), str(agat), str(gxf)],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        return "100.00"
    for line in r.stderr.splitlines():
        if "parity=" in line:
            return line.split("parity=")[1].strip().rstrip("%")
    return "NA"


def fmt_secs(s: float) -> str:
    return f"{s*1000:.0f} ms" if s < 1 else f"{s:.2f} s"


def human_kb(kb: str) -> str:
    try:
        v = int(kb)
    except (ValueError, TypeError):
        return "NA"
    return f"{v/1_048_576:.2f} GB" if v >= 1_048_576 else f"{v/1024:.0f} MB"


def main(argv: list[str]) -> int:
    results = Path(argv[1])
    normalizer = Path(argv[2])
    readme = Path(argv[3]) if len(argv) > 3 else None

    rows = []
    metrics = results / "metrics.tsv"
    if not metrics.exists():
        print(f"no metrics at {metrics}", file=sys.stderr)
        return 1
    lines = metrics.read_text().splitlines()
    for line in lines[1:]:  # skip header
        parts = line.split("\t")
        if len(parts) != 5:
            continue
        name, agat_s, agat_mem, gxf_s, gxf_mem = parts
        try:
            a = float(agat_s)
        except ValueError:
            a = None
        try:
            g = float(gxf_s)
        except ValueError:
            g = None
        speed = f"{a/g:.1f}×" if a and g else "NA"
        par = parity_rate(
            normalizer, results / f"{name}.agat.gtf", results / f"{name}.gxfkit.gtf"
        )
        rows.append(
            {
                "file": name,
                "agat_s": agat_s,
                "gxf_s": gxf_s,
                "agat_disp": fmt_secs(a) if a else "NA",
                "gxf_disp": fmt_secs(g) if g else "NA",
                "speed": speed,
                "agat_mem": human_kb(agat_mem),
                "gxf_mem": human_kb(gxf_mem),
                "parity": par,
            }
        )

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
        if a in text and b in text:
            pre = text[: text.index(a) + len(a)]
            post = text[text.index(b):]
            readme.write_text(f"{pre}\n{table}\n{post}", encoding="utf-8")
            print(f"\n[injected table into {readme}]", file=sys.stderr)

    # Optional CI gate: fail if any file's parity drops below MIN_PARITY.
    import os

    floor = os.environ.get("MIN_PARITY")
    if floor:
        floor = float(floor)
        bad = [r for r in rows if r["parity"] != "NA" and float(r["parity"]) < floor]
        if bad:
            for r in bad:
                print(
                    f"PARITY REGRESSION: {r['file']} {r['parity']}% < {floor}%",
                    file=sys.stderr,
                )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
