#!/usr/bin/env python3
"""Check docs/PARITY.md matches the current release parity gate."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
DOC = ROOT / "docs" / "PARITY.md"


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"docs/PARITY.md must mention: {needle}")


def forbid(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) in compact(text):
        errors.append(f"docs/PARITY.md must not mention: {needle}")


def main() -> int:
    text = DOC.read_text(encoding="utf-8")
    errors: list[str] = []

    for snippet in (
        "AGAT `1.7.0`",
        "enforced by CI at 100%",
        "| core     | human_chr1        | ~316k  | **100.00%** | none",
        "| core     | human_chr21       | ~40k   | **100.00%** | none",
        "| core     | yeast             | ~28.7k | **100.00%** | none",
        "| extended | drosophila        | ~506k  | **44.91%**",
        "benchmark/write-residuals.sh benchmark/results",
    ):
        require(text, snippet, errors)

    forbid(text, "enforced by CI at >=98%", errors)
    forbid(text, "enforced by CI at ≥98%", errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("verified parity doc")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
