#!/usr/bin/env python3
"""Syntax-check repository Python files without creating __pycache__ files."""
from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".git", "target"}
EXCLUDED_PREFIXES = (
    Path("benchmark") / "results",
    Path("corpus") / "raw",
)


def excluded(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if any(part in EXCLUDED_DIRS for part in rel.parts):
        return True
    return any(rel == prefix or prefix in rel.parents for prefix in EXCLUDED_PREFIXES)


def main() -> int:
    for path in sorted(ROOT.rglob("*.py")):
        if excluded(path):
            continue
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path.relative_to(ROOT)))
    print("verified python script syntax")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
