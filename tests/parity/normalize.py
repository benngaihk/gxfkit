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
        # also report counts + a parity rate (fraction of A's lines reproduced)
        sa, sb = set(a), set(b)
        matched = len(sa & sb)
        denom = max(len(sa), 1)
        rate = 100.0 * matched / denom
        print(f"\nSUMMARY: {len(a)} (A) vs {len(b)} (B) lines; "
              f"matched={matched}; only-in-A={len(sa - sb)}, only-in-B={len(sb - sa)}; "
              f"parity={rate:.2f}%", file=sys.stderr)
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
