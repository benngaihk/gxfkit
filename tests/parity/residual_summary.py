#!/usr/bin/env python3
"""Summarize normalized AGAT-vs-gxfkit residuals by feature and ID family.

This is a diagnostic companion to normalize.py. It keeps normalize.py as the
actual pass/fail oracle, then groups the remaining value-preserving diffs so the
parity ledger can say what is left without hand-written awk.

Usage:
    python residual_summary.py agat.gtf gxfkit.gtf
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from normalize import multiset_parity, normalize_lines, parse_attrs


SYNTH_ID_RE = re.compile(r"^agat-(.+)-\d+$")
SYNTH_VALUE_RE = re.compile(r"agat-([A-Za-z0-9_]+)-(\d+)")


def family(line: str) -> tuple[str, str]:
    cols = line.split("\t")
    if len(cols) != 9:
        return ("~non-gtf", "~non-gtf")
    attrs = dict(parse_attrs(cols[8]))
    feature_type = cols[2]
    for key in ("ID", "gene_id"):
        value = attrs.get(key, "")
        match = SYNTH_ID_RE.match(value)
        if match:
            return (feature_type, f"{key}:agat-{match.group(1)}")
    return (feature_type, "source-or-other")


def read_norm(path: str) -> set[str]:
    return set(normalize_lines(Path(path).read_text(encoding="utf-8")))


def counter_canonical(line: str) -> str:
    return SYNTH_VALUE_RE.sub(lambda m: f"agat-{m.group(1)}-#", line)


def synthetic_values(line: str) -> list[tuple[str, int]]:
    return [(m.group(1), int(m.group(2))) for m in SYNTH_VALUE_RE.finditer(line)]


def seqid_for(line: str) -> str:
    cols = line.split("\t")
    return cols[0] if len(cols) == 9 else "~non-gtf"


def raw_synthetic_family(line: str) -> tuple[str, str, int] | None:
    cols = line.split("\t")
    if len(cols) != 9:
        return None
    attrs = dict(parse_attrs(cols[8]))
    for key in ("ID", "gene_id"):
        value = attrs.get(key, "")
        match = SYNTH_ID_RE.match(value)
        if match:
            return (f"agat-{match.group(1)}", key, int(value.rsplit("-", 1)[1]))
    return None


def first_seqids(rows: list[tuple[int, int, str, str, int, int]], by_counter: bool) -> str:
    index = 0 if by_counter else 1
    seen: set[str] = set()
    out: list[str] = []
    for row in sorted(rows, key=lambda row: (row[index], row[2], row[4], row[5])):
        seqid = row[2]
        if seqid not in seen:
            seen.add(seqid)
            out.append(seqid)
    return ",".join(out[:16]) + (f",...(+{len(out) - 16})" if len(out) > 16 else "")


def print_raw_counter_order(label: str, path: str) -> None:
    by_family: dict[str, list[tuple[int, int, str, str, int, int]]] = defaultdict(list)
    with Path(path).open(encoding="utf-8") as fh:
        for line_no, raw in enumerate(fh, 1):
            line = raw.rstrip()
            if not line or line.startswith("#"):
                continue
            found = raw_synthetic_family(line)
            if found is None:
                continue
            family_name, key, counter = found
            cols = line.split("\t")
            if key == "gene_id" and cols[2] != "RNA":
                # Keep propagated synthetic gene IDs from child rows from
                # dominating the order diagnostic. The residual counter report
                # above still counts every occurrence.
                continue
            by_family[family_name].append(
                (counter, line_no, cols[0], cols[2], int(cols[3]), int(cols[4]))
            )

    print(f"raw counter order ({label}):")
    for family_name, rows in sorted(by_family.items(), key=lambda kv: kv[0]):
        if not rows:
            continue
        by_line = [counter for counter, *_ in sorted(rows, key=lambda row: row[1])]
        inversions = sum(1 for a, b in zip(by_line, by_line[1:]) if b < a)
        print(
            f"  family={family_name}\trows={len(rows)}\t"
            f"line_counter_inversions={inversions}\t"
            f"seqids_by_counter={first_seqids(rows, by_counter=True)}\t"
            f"seqids_by_line={first_seqids(rows, by_counter=False)}"
        )


def first_counter_runs(rows: list[tuple[int, int, str, str]], use_agat: bool) -> str:
    """Compact the first seqid runs in counter order.

    This is intentionally diagnostic, not part of the oracle. A short run list
    makes it obvious when one side uses plain seqid traversal while AGAT is
    assigning counters in another internal order.
    """
    index = 0 if use_agat else 1
    by_number: dict[int, str] = {}
    for row in sorted(rows, key=lambda row: (row[index], row[2])):
        by_number.setdefault(row[index], row[2])
    ordered = sorted((num, seqid) for num, seqid in by_number.items())
    runs: list[list[object]] = []
    for num, seqid in ordered:
        if runs and runs[-1][0] == seqid and int(runs[-1][2]) + 1 == num:
            runs[-1][2] = num
            runs[-1][3] = int(runs[-1][3]) + 1
        else:
            runs.append([seqid, num, num, 1])
        if len(runs) >= 8:
            break
    return ", ".join(
        f"{seqid}:{start}-{end}({count})" if start != end else f"{seqid}:{start}({count})"
        for seqid, start, end, count in runs
    )


def counter_seqid_order(
    rows: list[tuple[int, int, str, str]], use_agat: bool, limit: int = 24
) -> str:
    """Seqids in first-seen order when sorted by one side's synthetic counter."""
    index = 0 if use_agat else 1
    seen: set[str] = set()
    ordered: list[str] = []
    for row in sorted(rows, key=lambda row: (row[index], row[2])):
        seqid = row[2]
        if seqid not in seen:
            seen.add(seqid)
            ordered.append(seqid)
    shown = ordered[:limit]
    suffix = f",...(+{len(ordered) - limit})" if len(ordered) > limit else ""
    return ",".join(shown) + suffix


def print_counts(title: str, lines: set[str]) -> None:
    print(title)
    by_feature = Counter()
    by_family = Counter()
    for line in lines:
        feature_type, fam = family(line)
        by_feature[feature_type] += 1
        by_family[(feature_type, fam)] += 1

    print("  by feature_type:")
    for feature_type, count in by_feature.most_common(12):
        print(f"    {feature_type}\t{count}")
    print("  by synthetic family:")
    for (feature_type, fam), count in by_family.most_common(12):
        print(f"    {feature_type}\t{fam}\t{count}")


def print_counter_drift(a_only: set[str], b_only: set[str]) -> None:
    a_by_canon: dict[str, list[str]] = defaultdict(list)
    b_by_canon: dict[str, list[str]] = defaultdict(list)
    for line in a_only:
        if SYNTH_VALUE_RE.search(line):
            a_by_canon[counter_canonical(line)].append(line)
    for line in b_only:
        if SYNTH_VALUE_RE.search(line):
            b_by_canon[counter_canonical(line)].append(line)

    paired: list[tuple[str, str]] = []
    ambiguous_a = ambiguous_b = unpaired_a = unpaired_b = 0
    for key, a_lines in a_by_canon.items():
        b_lines = b_by_canon.pop(key, [])
        if len(a_lines) == len(b_lines) == 1:
            paired.append((a_lines[0], b_lines[0]))
        elif b_lines:
            ambiguous_a += len(a_lines)
            ambiguous_b += len(b_lines)
        else:
            unpaired_a += len(a_lines)
    unpaired_b = sum(len(lines) for lines in b_by_canon.values())

    print("counter drift:")
    print(
        f"  paired={len(paired)} ambiguous_a={ambiguous_a} "
        f"ambiguous_b={ambiguous_b} unpaired_a={unpaired_a} unpaired_b={unpaired_b}"
    )

    by_family: dict[str, list[tuple[int, int, str, str]]] = defaultdict(list)
    for a_line, b_line in paired:
        a_values = synthetic_values(a_line)
        b_values = synthetic_values(b_line)
        for (a_family, a_num), (b_family, b_num) in zip(a_values, b_values):
            if a_family != b_family or a_num == b_num:
                continue
            cols = a_line.split("\t")
            seqid = cols[0] if len(cols) == 9 else "~non-gtf"
            feature_type = cols[2] if len(cols) == 9 else "~non-gtf"
            by_family[a_family].append((a_num, b_num, seqid, feature_type))

    for family, rows in sorted(by_family.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        diffs = [a_num - b_num for a_num, b_num, _, _ in rows]
        seq_counts = Counter(seqid for _, _, seqid, _ in rows)
        type_counts = Counter(feature_type for _, _, _, feature_type in rows)
        top_seqids = ",".join(f"{seqid}:{count}" for seqid, count in seq_counts.most_common(6))
        top_types = ",".join(
            f"{feature_type}:{count}" for feature_type, count in type_counts.most_common(6)
        )
        print(
            f"  family=agat-{family}\toccurrences={len(rows)}\t"
            f"diff_min={min(diffs)}\tdiff_max={max(diffs)}\t"
            f"top_seqids={top_seqids}\ttop_types={top_types}"
        )
        print(
            f"    counter_runs_agat={first_counter_runs(rows, use_agat=True)}\t"
            f"counter_runs_gxfkit={first_counter_runs(rows, use_agat=False)}"
        )
        print(
            f"    counter_seqids_agat={counter_seqid_order(rows, use_agat=True)}\t"
            f"counter_seqids_gxfkit={counter_seqid_order(rows, use_agat=False)}"
        )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    a_lines = normalize_lines(Path(argv[1]).read_text(encoding="utf-8"))
    b_lines = normalize_lines(Path(argv[2]).read_text(encoding="utf-8"))
    matched, only_a_count, only_b_count, parity = multiset_parity(a_lines, b_lines)
    a = set(a_lines)
    b = set(b_lines)
    print(
        f"SUMMARY matched={matched} only_in_a={only_a_count} "
        f"only_in_b={only_b_count} parity={parity:.2f}%"
    )
    print_counts("only in A", a - b)
    print_counts("only in B", b - a)
    print_counter_drift(a - b, b - a)
    print_raw_counter_order("A", argv[1])
    print_raw_counter_order("B", argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
