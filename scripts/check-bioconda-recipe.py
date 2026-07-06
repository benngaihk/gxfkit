#!/usr/bin/env python3
"""Validate the local Bioconda recipe without requiring bioconda-utils."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def read(root: Path, path: str) -> str:
    return (root / path).read_text(encoding="utf-8")


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def require_contains(text: str, snippet: str, label: str, errors: list[str]) -> None:
    require(snippet in text, f"{label} missing: {snippet}", errors)


def validate_meta_pair(root: Path, errors: list[str]) -> None:
    recipe_path = "packaging/bioconda/recipe/meta.yaml"
    template_path = "packaging/bioconda/meta.yaml.template"
    recipe = read(root, recipe_path)
    template = read(root, template_path)

    require(recipe == template, "Bioconda recipe and template are not identical", errors)
    for path, text in ((recipe_path, recipe), (template_path, template)):
        require_contains(text, '{% set name = "gxfkit" %}', path, errors)
        require_contains(text, '{% set version = "', path, errors)
        require_contains(
            text,
            "url: https://github.com/benngaihk/gxfkit/archive/refs/tags/v{{ version }}.tar.gz",
            path,
            errors,
        )
        require(
            re.search(r"(?m)^  sha256: [0-9a-f]{64}$", text) is not None,
            f"{path} missing 64-hex source sha256",
            errors,
        )
        require("run_exports" not in text, f"{path} must not declare run_exports", errors)
        require_contains(text, "build:\n  number: 0", path, errors)
        require_contains(text, "- {{ compiler('rust') }}", path, errors)
        require_contains(text, "- {{ compiler('c') }}", path, errors)
        require_contains(text, "- {{ stdlib('c') }}", path, errors)
        require_contains(text, "- cargo-bundle-licenses", path, errors)
        require_contains(text, "test:\n  commands:", path, errors)
        require_contains(text, "- gxfkit version", path, errors)
        require_contains(text, "cat > smoke.gff3 <<'GFF'", path, errors)
        require_contains(text, "gxfkit gff2gtf -g smoke.gff3 -o smoke.gtf", path, errors)
        require_contains(text, "grep 'gene_id \"g1\"; transcript_id \"t1\";' smoke.gtf", path, errors)
        require_contains(
            text,
            "if gxfkit gff2gtf -g smoke.gff3 -o smoke.gtf 2> overwrite.err; then",
            path,
            errors,
        )
        require_contains(text, "grep 'refusing to overwrite' overwrite.err", path, errors)
        require_contains(text, "license: MIT", path, errors)
        require_contains(text, "license_family: MIT", path, errors)
        require_contains(text, "- LICENSE", path, errors)
        require_contains(text, "- THIRDPARTY.yml", path, errors)
        require_contains(
            text,
            "summary: Fast AGAT-compatible GFF/GTF command-line utilities",
            path,
            errors,
        )
        require_contains(text, "recipe-maintainers:\n    - benngaihk", path, errors)


def validate_build_script(root: Path, errors: list[str]) -> None:
    path = "packaging/bioconda/recipe/build.sh"
    text = read(root, path)
    require_contains(text, "set -euo pipefail", path, errors)
    require_contains(
        text,
        "cargo-bundle-licenses --format yaml --output THIRDPARTY.yml",
        path,
        errors,
    )
    require_contains(
        text,
        'cargo install --locked --no-track --root "${PREFIX}" --path crates/gxfkit',
        path,
        errors,
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1], type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = args.root.resolve()
    errors: list[str] = []
    validate_meta_pair(root, errors)
    validate_build_script(root, errors)
    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print("verified Bioconda recipe")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
