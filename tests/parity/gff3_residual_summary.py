#!/usr/bin/env python3
"""Summarize normalized AGAT-vs-gxfkit GFF3 residuals.

This is the GFF3 companion to residual_summary.py. It is intentionally
conservative: normalization absorbs only comments, line order, whitespace, and
attribute order. Values, coordinates, sources, feature types, IDs, and Parent
links remain part of the oracle-facing diff.

Usage:
    python gff3_residual_summary.py agat.gff3 gxfkit.gff3
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

SYNTH_ID_RE = re.compile(r"^agat-(.+)-\d+$")
SYNTH_VALUE_RE = re.compile(r"agat-([A-Za-z0-9_]+)-(\d+)")


def parse_attrs(col: str) -> list[tuple[str, str]]:
    if col == "." or not col:
        return []
    pairs = []
    for field in col.split(";"):
        field = field.strip()
        if not field:
            continue
        if "=" in field:
            key, value = field.split("=", 1)
            pairs.append((key.strip(), value))
        else:
            pairs.append((field, ""))
    return pairs


def canon_attr_col(col: str) -> str:
    pairs = parse_attrs(col)
    if not pairs:
        return "."
    pinned_order = {"ID": 0, "Parent": 1}
    pinned = [p for p in pairs if p[0] in pinned_order]
    rest = [p for p in pairs if p[0] not in pinned_order]
    pinned.sort(key=lambda p: pinned_order[p[0]])
    rest.sort(key=lambda p: p[0])
    return ";".join(f"{key}={value}" for key, value in pinned + rest)


def normalize_lines(text: str) -> list[str]:
    out: list[tuple[tuple[object, ...], str]] = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 9:
            out.append((("~", line), line))
            continue
        cols[8] = canon_attr_col(cols[8])
        attrs = dict(parse_attrs(cols[8]))
        key = (
            cols[0],
            int(cols[3]) if cols[3].isdigit() else cols[3],
            int(cols[4]) if cols[4].isdigit() else cols[4],
            cols[2],
            attrs.get("ID", ""),
            attrs.get("Parent", ""),
            cols[8],
        )
        out.append((key, "\t".join(cols)))
    out.sort(key=lambda kv: kv[0])
    return [line for _, line in out]


def multiset_parity(a: list[str], b: list[str]) -> tuple[int, int, int, float]:
    ca = Counter(a)
    cb = Counter(b)
    keys = set(ca) | set(cb)
    matched = sum(min(ca[key], cb[key]) for key in keys)
    only_a = sum(max(ca[key] - cb[key], 0) for key in keys)
    only_b = sum(max(cb[key] - ca[key], 0) for key in keys)
    denom = max(matched + only_a + only_b, 1)
    return matched, only_a, only_b, 100.0 * matched / denom


def multiset_only(a: list[str], b: list[str]) -> list[str]:
    ca = Counter(a)
    cb = Counter(b)
    out: list[str] = []
    for key in sorted(set(ca) | set(cb)):
        out.extend([key] * max(ca[key] - cb[key], 0))
    return out


def synthetic_family_from_attrs(attrs: dict[str, str]) -> str | None:
    for key in ("ID", "Parent", "gene_id", "transcript_id"):
        value = attrs.get(key, "")
        for item in value.split(","):
            match = SYNTH_ID_RE.match(item)
            if match:
                return f"{key}:agat-{match.group(1)}"
    return None


def family(line: str) -> tuple[str, str]:
    cols = line.split("\t")
    if len(cols) != 9:
        return ("~non-gff3", "~non-gff3")
    feature_type = cols[2]
    fam = synthetic_family_from_attrs(dict(parse_attrs(cols[8])))
    return (feature_type, fam or "source-or-other")


def counter_canonical(line: str) -> str:
    return SYNTH_VALUE_RE.sub(lambda m: f"agat-{m.group(1)}-#", line)


def synthetic_values(line: str) -> list[tuple[str, int]]:
    return [(m.group(1), int(m.group(2))) for m in SYNTH_VALUE_RE.finditer(line)]


def print_counts(title: str, lines: list[str]) -> None:
    print(title)
    by_feature = Counter()
    by_family = Counter()
    for line in lines:
        feature_type, fam = family(line)
        by_feature[feature_type] += 1
        by_family[(feature_type, fam)] += 1

    print("  by feature_type:")
    for feature_type, count in by_feature.most_common(16):
        print(f"    {feature_type}\t{count}")
    print("  by synthetic family:")
    for (feature_type, fam), count in by_family.most_common(16):
        print(f"    {feature_type}\t{fam}\t{count}")


def print_counter_drift(a_only: list[str], b_only: list[str]) -> None:
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

    by_family = Counter()
    for a_line, b_line in paired:
        for (a_family, a_num), (b_family, b_num) in zip(
            synthetic_values(a_line), synthetic_values(b_line)
        ):
            if a_family == b_family and a_num != b_num:
                by_family[f"agat-{a_family}"] += 1
    for family_name, count in by_family.most_common(16):
        print(f"  family={family_name}\tpaired_counter_drift={count}")


def raw_synthetic_family(line: str) -> tuple[str, str, int] | None:
    cols = line.split("\t")
    if len(cols) != 9:
        return None
    attrs = dict(parse_attrs(cols[8]))
    for key in ("ID", "Parent", "gene_id", "transcript_id"):
        value = attrs.get(key, "")
        for item in value.split(","):
            match = SYNTH_ID_RE.match(item)
            if match:
                return (f"agat-{match.group(1)}", key, int(item.rsplit("-", 1)[1]))
    return None


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
            if key in {"Parent", "gene_id", "transcript_id"} and cols[2] not in {"RNA", "mRNA"}:
                continue
            by_family[family_name].append(
                (counter, line_no, cols[0], cols[2], int(cols[3]), int(cols[4]))
            )

    print(f"raw counter order ({label}):")
    for family_name, rows in sorted(by_family.items(), key=lambda kv: kv[0]):
        by_line = [counter for counter, *_ in sorted(rows, key=lambda row: row[1])]
        inversions = sum(1 for a, b in zip(by_line, by_line[1:]) if b < a)
        seqids_by_counter = first_seqids(rows, by_counter=True)
        seqids_by_line = first_seqids(rows, by_counter=False)
        print(
            f"  family={family_name}\trows={len(rows)}\t"
            f"line_counter_inversions={inversions}\t"
            f"seqids_by_counter={seqids_by_counter}\tseqids_by_line={seqids_by_line}"
        )


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


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2

    a = normalize_lines(Path(argv[1]).read_text(encoding="utf-8"))
    b = normalize_lines(Path(argv[2]).read_text(encoding="utf-8"))
    matched, only_a_count, only_b_count, parity = multiset_parity(a, b)
    a_only = multiset_only(a, b)
    b_only = multiset_only(b, a)

    print(
        f"SUMMARY\tlines_a={len(a)}\tlines_b={len(b)}\tmatched={matched}\t"
        f"only_a={only_a_count}\tonly_b={only_b_count}\tparity={parity:.2f}%"
    )
    print_counts("only-in-AGAT", a_only)
    print_counts("only-in-gxfkit", b_only)
    print_counter_drift(a_only, b_only)
    print_raw_counter_order("AGAT", argv[1])
    print_raw_counter_order("gxfkit", argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
