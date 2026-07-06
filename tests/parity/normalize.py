#!/usr/bin/env python3
"""Normalize a GTF file so that two semantically-equivalent files compare equal.

The point of parity testing is to prove gxfkit's output *means* the same thing
as AGAT's, not that we reproduce every incidental byte. This normalizer absorbs
differences that are genuinely harmless, and *nothing else* — anything it cannot
justify as harmless is left in place so a real divergence still shows up in diff.

What it normalizes (all reversible / order-only / whitespace-only):
  * line order: feature lines are sorted by a stable key
    (seqid, start, end, feature_type, gene_id, transcript_id, raw attrs);
  * comment / track / empty lines are dropped;
  * trailing whitespace and CRLF vs LF;
  * spacing inside the attribute column (`k "v";` canonical single-space form);
  * attribute order *within a line* is sorted, EXCEPT gene_id/transcript_id which
    are pinned first (GTF spec requires them leading) — so a tool emitting the
    same attributes in a different order is treated as equal.

What it deliberately does NOT touch (would hide real bugs):
  * attribute values, coordinates, strand, phase, feature types, sources;
  * presence/absence of any attribute or feature line.

Usage:
    python normalize.py in.gtf            # write normalized form to stdout
    python normalize.py a.gtf b.gtf       # exit 0 if equal, 1 + unified diff
"""
from __future__ import annotations

import re
import sys
from collections import Counter

_ATTR_RE = re.compile(r'(\w+)\s+"((?:[^"\\]|\\.)*)"\s*;')


def parse_attrs(col: str) -> list[tuple[str, str]]:
    return [(m.group(1), m.group(2)) for m in _ATTR_RE.finditer(col)]


def canon_attr_col(col: str) -> str:
    pairs = parse_attrs(col)
    pinned = [p for p in pairs if p[0] in ("gene_id", "transcript_id")]
    # keep gene_id before transcript_id
    pinned.sort(key=lambda p: 0 if p[0] == "gene_id" else 1)
    rest = sorted(p for p in pairs if p[0] not in ("gene_id", "transcript_id"))
    return " ".join(f'{k} "{v}";' for k, v in pinned + rest)


def normalize_lines(text: str) -> list[str]:
    out = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 9:
            # Pass through non-conforming lines verbatim so they surface in diff.
            out.append((("~", line), line))
            continue
        cols[8] = canon_attr_col(cols[8])
        attrs = dict(parse_attrs(cols[8]))
        key = (
            cols[0],                      # seqid
            int(cols[3]) if cols[3].isdigit() else cols[3],  # start
            int(cols[4]) if cols[4].isdigit() else cols[4],  # end
            cols[2],                      # feature_type
            attrs.get("gene_id", ""),
            attrs.get("transcript_id", ""),
            cols[8],
        )
        out.append((key, "\t".join(cols)))
    out.sort(key=lambda kv: kv[0])
    return [line for _, line in out]


def multiset_parity(a: list[str], b: list[str]) -> tuple[int, int, int, float]:
    """Return overlap/only-A/only-B and a symmetric multiset parity percentage."""
    ca = Counter(a)
    cb = Counter(b)
    keys = set(ca) | set(cb)
    matched = sum(min(ca[key], cb[key]) for key in keys)
    only_a = sum(max(ca[key] - cb[key], 0) for key in keys)
    only_b = sum(max(cb[key] - ca[key], 0) for key in keys)
    denom = max(matched + only_a + only_b, 1)
    return matched, only_a, only_b, 100.0 * matched / denom


def main(argv: list[str]) -> int:
    if len(argv) == 2:
        with open(argv[1], encoding="utf-8") as fh:
            for line in normalize_lines(fh.read()):
                print(line)
        return 0
    if len(argv) == 3:
        with open(argv[1], encoding="utf-8") as fa, open(argv[2], encoding="utf-8") as fb:
            a = normalize_lines(fa.read())
            b = normalize_lines(fb.read())
        if a == b:
            print(f"PARITY OK: {argv[1]} == {argv[2]} ({len(a)} lines)")
            return 0
        import difflib

        diff = difflib.unified_diff(a, b, argv[1], argv[2], lineterm="", n=2)
        shown = 0
        for d in diff:
            print(d)
            shown += 1
            if shown > 80:
                print("... (diff truncated)")
                break
        # Also report counts + a symmetric multiset parity rate. Extra gxfkit
        # lines are divergences too because AGAT is the correctness oracle.
        matched, only_a, only_b, rate = multiset_parity(a, b)
        print(f"\nSUMMARY: {len(a)} (A) vs {len(b)} (B) lines; "
              f"matched={matched}; only-in-A={only_a}, only-in-B={only_b}; "
              f"parity={rate:.2f}%", file=sys.stderr)
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
