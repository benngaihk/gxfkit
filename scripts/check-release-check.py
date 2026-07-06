#!/usr/bin/env python3
"""Check scripts/release-check.sh keeps local preflight deterministic."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
SCRIPT = ROOT / "scripts" / "release-check.sh"


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"scripts/release-check.sh must contain: {needle}")


def forbid(text: str, needle: str, errors: list[str]) -> None:
    if compact(needle) in compact(text):
        errors.append(f"scripts/release-check.sh must not contain: {needle}")


def require_order(text: str, first: str, second: str, errors: list[str]) -> None:
    first_index = compact(text).find(compact(first))
    second_index = compact(text).find(compact(second))
    if first_index == -1 or second_index == -1 or first_index >= second_index:
        errors.append(
            "scripts/release-check.sh must run "
            f"{first!r} before {second!r}"
        )


def require_all_test_scripts(text: str, errors: list[str]) -> None:
    for test_script in sorted((ROOT / "scripts").glob("test-*")):
        if not test_script.is_file():
            continue
        require(text, f"scripts/{test_script.name}", errors)


def main() -> int:
    text = SCRIPT.read_text(encoding="utf-8")
    errors: list[str] = []

    for snippet in (
        'PACKAGE_NETWORK="${RELEASE_CHECK_PACKAGE_NETWORK:-0}"',
        "RELEASE_CHECK_PACKAGE_NETWORK must be 0 or 1",
        "package_args=(--locked --allow-dirty --registry crates-io)",
        'if [ "$PACKAGE_NETWORK" = 0 ]; then',
        "package_args+=(--offline)",
        "bash scripts/test-local-cargo-install-verifier.sh",
        'VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="$CARGO_BIN" bash scripts/verify-local-cargo-install.sh',
        '"$CARGO_BIN" package -p gxfkit-core "${package_args[@]}"',
        '"$CARGO_BIN" package -p gxfkit "${package_args[@]}"',
        "bash scripts/test-release-artifacts.sh",
        "python3 scripts/check-release-artifacts.py",
        "bash scripts/test-release-check.sh",
        "python3 scripts/check-release-check.py",
    ):
        require(text, snippet, errors)

    for snippet in (
        "PACKAGE_CARGO_HOME",
        'CARGO_HOME="$PACKAGE_CARGO_HOME"',
    ):
        forbid(text, snippet, errors)

    require_order(
        text,
        "bash scripts/test-local-cargo-install-verifier.sh",
        'VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="$CARGO_BIN" bash scripts/verify-local-cargo-install.sh',
        errors,
    )
    require_order(
        text,
        "package_args+=(--offline)",
        '"$CARGO_BIN" package -p gxfkit-core "${package_args[@]}"',
        errors,
    )
    require_order(
        text,
        "bash scripts/test-release-archive-verifier.sh",
        "bash scripts/test-release-artifacts.sh",
        errors,
    )
    require_order(
        text,
        "bash scripts/test-release-artifacts.sh",
        "python3 scripts/check-release-artifacts.py",
        errors,
    )
    require_order(
        text,
        "bash scripts/test-release-check.sh",
        "python3 scripts/check-release-check.py",
        errors,
    )

    require_all_test_scripts(text, errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("verified release-check contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
