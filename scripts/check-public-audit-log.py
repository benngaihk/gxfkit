#!/usr/bin/env python3
"""Validate a recorded public install audit log."""
from __future__ import annotations

import argparse
from collections import Counter
import re
import sys
from pathlib import Path
from typing import Callable


DEFAULT_CHANNELS = "github-linux github-parity bioconda crates"
DEFAULT_NO_OVERWRITE = "1"
DEFAULT_MIN_PARITY = "100"
DEFAULT_BENCH_FILES = "human_chr1 human_chr21 yeast"
DEFAULT_CRATES_INSTALL_SCRIPT = "scripts/verify-crates-install.sh"
KNOWN_CHANNELS = {"github-linux", "github-parity", "bioconda", "crates"}
VERSION_RE = re.compile(r"^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$")
BENCH_FILE_RE = re.compile(r"^[A-Za-z0-9._-]+$")
ALLOWED_METADATA_KEYS = {
    "public-audit-allow-missing-crates",
    "public-audit-bench-files",
    "public-audit-channels",
    "public-audit-crates-install-script",
    "public-audit-exit-code",
    "public-audit-min-parity",
    "public-audit-no-overwrite",
    "public-audit-tag",
    "public-audit-version",
}
SUMMARY_RE = re.compile(
    r"^public install summary: "
    r"passed=\[(?P<passed>[^\]]*)\] "
    r"allowed_missing=\[(?P<allowed_missing>[^\]]*)\] "
    r"failed=\[(?P<failed>[^\]]*)\]$"
)


def parse_list(value: str) -> set[str]:
    return {item for item in value.split() if item}


def parse_items(value: str) -> list[str]:
    return [item for item in value.split() if item]


def parse_channels(value: str) -> list[str]:
    items = parse_items(value)
    if not items:
        raise argparse.ArgumentTypeError("channels must not be empty")
    duplicates = sorted(channel for channel, count in Counter(items).items() if count > 1)
    if duplicates:
        raise argparse.ArgumentTypeError(f"channels must not repeat: {', '.join(duplicates)}")
    unknown = sorted(set(items) - KNOWN_CHANNELS)
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown channels: {', '.join(unknown)}")
    return items


def parse_version(value: str) -> str:
    if not VERSION_RE.fullmatch(value):
        raise argparse.ArgumentTypeError(f"must look like X.Y.Z, got: {value}")
    return value


def parse_tag(value: str) -> str:
    if not value.startswith("v"):
        raise argparse.ArgumentTypeError(f"must start with v, got: {value}")
    version = value[1:]
    if not VERSION_RE.fullmatch(version):
        raise argparse.ArgumentTypeError(f"must look like vX.Y.Z, got: {value}")
    return value


def parse_binary_setting(value: str) -> str:
    if value not in {"0", "1"}:
        raise argparse.ArgumentTypeError(f"must be 0 or 1, got: {value}")
    return value


def parse_min_parity(value: str) -> str:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"must be a number, got: {value}") from exc
    if not 0 <= parsed <= 100:
        raise argparse.ArgumentTypeError(f"must be between 0 and 100, got: {value}")
    return value


def parse_bench_files(value: str) -> str:
    items = parse_items(value)
    if not items:
        raise argparse.ArgumentTypeError("must include at least one corpus name")
    duplicates = sorted(item for item, count in Counter(items).items() if count > 1)
    if duplicates:
        raise argparse.ArgumentTypeError(f"must not repeat: {', '.join(duplicates)}")
    for item in items:
        if not BENCH_FILE_RE.fullmatch(item) or item in {".", ".."}:
            raise argparse.ArgumentTypeError(f"entries must be corpus basenames, got: {item}")
    return value


def parse_crates_install_script(value: str) -> str:
    if not value:
        raise argparse.ArgumentTypeError("must not be empty")
    if any(char.isspace() for char in value):
        raise argparse.ArgumentTypeError(
            f"must be a repository-relative scripts/*.sh path without whitespace, got: {value}"
        )
    if value.startswith("/") or value.startswith("-"):
        raise argparse.ArgumentTypeError(
            f"must be a repository-relative scripts/*.sh path, got: {value}"
        )
    parts = value.split("/")
    if ".." in parts:
        raise argparse.ArgumentTypeError(
            f"must be a repository-relative scripts/*.sh path, got: {value}"
        )
    if not value.startswith("scripts/") or not value.endswith(".sh"):
        raise argparse.ArgumentTypeError(
            f"must be a repository-relative scripts/*.sh path, got: {value}"
        )
    return value


def check_duplicate_list_items(label: str, value: str, errors: list[str]) -> None:
    duplicates = sorted(item for item, count in Counter(parse_items(value)).items() if count > 1)
    if duplicates:
        errors.append(f"{label} must not repeat: {', '.join(duplicates)}")


def validate_metadata_value(
    label: str,
    value: str,
    parser: Callable[[str], object],
    errors: list[str],
) -> None:
    try:
        parser(value)
    except argparse.ArgumentTypeError as exc:
        errors.append(f"public audit {label} {exc}")


def parse_metadata(text: str, errors: list[str]) -> dict[str, str]:
    items = re.findall(r"(?m)^(public-audit-[A-Za-z0-9-]+)=(.*)$", text)
    metadata: dict[str, str] = {}
    seen: set[str] = set()
    duplicates: set[str] = set()
    for key, value in items:
        if key in seen:
            duplicates.add(key)
            continue
        seen.add(key)
        metadata[key] = value
    for key in sorted(duplicates):
        errors.append(f"public audit log has duplicate metadata key: {key}")
    for key in sorted(seen - ALLOWED_METADATA_KEYS):
        errors.append(f"public audit log has unknown metadata key: {key}")
    return metadata


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", type=parse_version, help="expected release version recorded in the log")
    parser.add_argument("--tag", type=parse_tag, help="expected release tag recorded in the log")
    parser.add_argument(
        "--verify-no-overwrite",
        default=DEFAULT_NO_OVERWRITE,
        type=parse_binary_setting,
        help=f"expected no-overwrite setting recorded in the log (default: {DEFAULT_NO_OVERWRITE})",
    )
    parser.add_argument(
        "--min-parity",
        default=DEFAULT_MIN_PARITY,
        type=parse_min_parity,
        help=f"expected min parity recorded in the log (default: {DEFAULT_MIN_PARITY})",
    )
    parser.add_argument(
        "--bench-files",
        default=DEFAULT_BENCH_FILES,
        type=parse_bench_files,
        help=f"expected BENCH_FILES recorded in the log (default: {DEFAULT_BENCH_FILES!r})",
    )
    parser.add_argument(
        "--crates-install-script",
        default=DEFAULT_CRATES_INSTALL_SCRIPT,
        type=parse_crates_install_script,
        help=(
            "expected Crates.io install verifier script recorded in the log "
            f"(default: {DEFAULT_CRATES_INSTALL_SCRIPT!r})"
        ),
    )
    parser.add_argument(
        "--channels",
        default=DEFAULT_CHANNELS,
        type=parse_channels,
        help=f"space-separated channels expected in the log (default: {DEFAULT_CHANNELS!r})",
    )
    parser.add_argument(
        "--allow-missing-crates",
        action="store_true",
        help="allow crates to appear in allowed_missing instead of passed",
    )
    parser.add_argument("log", type=Path, help="public-audit.log to validate")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.version is not None and args.tag is not None and args.tag != f"v{args.version}":
        print(
            f"ERROR version and tag disagree: version={args.version} tag={args.tag}",
            file=sys.stderr,
        )
        return 2
    expected_channel_order = args.channels
    expected_channels = set(expected_channel_order)
    if not args.log.is_file():
        print(f"ERROR public audit log not found: {args.log}", file=sys.stderr)
        return 1

    text = args.log.read_text(encoding="utf-8")
    errors: list[str] = []
    metadata = parse_metadata(text, errors)
    actual_channels = metadata.get("public-audit-channels")
    if actual_channels is None:
        errors.append("public audit log is missing public-audit-channels")
    else:
        check_duplicate_list_items("public audit metadata channels", actual_channels, errors)
        actual_channel_order = parse_items(actual_channels)
        if parse_list(actual_channels) != expected_channels:
            errors.append(
                "public audit metadata channels must be "
                f"{sorted(expected_channels)}, got {sorted(parse_list(actual_channels))}"
            )
        elif actual_channel_order != expected_channel_order:
            errors.append(
                "public audit metadata channel order must be "
                f"{expected_channel_order}, got {actual_channel_order}"
            )
    actual_allow_missing = metadata.get("public-audit-allow-missing-crates")
    expected_allow_missing = "1" if args.allow_missing_crates else "0"
    if actual_allow_missing is None:
        errors.append("public audit log is missing public-audit-allow-missing-crates")
    else:
        validate_metadata_value("allow-missing-crates", actual_allow_missing, parse_binary_setting, errors)
    if actual_allow_missing is not None and actual_allow_missing != expected_allow_missing:
        errors.append(
            "public audit allow-missing-crates must be "
            f"{expected_allow_missing}, got {actual_allow_missing}"
        )
    actual_version = metadata.get("public-audit-version")
    actual_tag = metadata.get("public-audit-tag")
    if actual_version is None:
        errors.append("public audit log is missing public-audit-version")
    elif not VERSION_RE.fullmatch(actual_version):
        errors.append(f"public audit version must look like X.Y.Z, got {actual_version}")
    elif args.version is not None and actual_version != args.version:
        errors.append(f"public audit version must be {args.version}, got {actual_version}")
    if actual_tag is None:
        errors.append("public audit log is missing public-audit-tag")
    elif not actual_tag.startswith("v"):
        errors.append(f"public audit tag must start with v, got {actual_tag}")
    elif not VERSION_RE.fullmatch(actual_tag[1:]):
        errors.append(f"public audit tag must look like vX.Y.Z, got {actual_tag}")
    elif args.tag is not None and actual_tag != args.tag:
        errors.append(f"public audit tag must be {args.tag}, got {actual_tag}")
    if actual_version is not None and actual_tag is not None and actual_tag != f"v{actual_version}":
        errors.append(f"public audit version and tag disagree: version={actual_version} tag={actual_tag}")
    for option_name, metadata_name, label in (
        ("verify_no_overwrite", "public-audit-no-overwrite", "no-overwrite"),
        ("min_parity", "public-audit-min-parity", "min parity"),
        ("bench_files", "public-audit-bench-files", "bench files"),
        ("crates_install_script", "public-audit-crates-install-script", "crates install script"),
    ):
        expected = getattr(args, option_name)
        if expected is None:
            continue
        actual = metadata.get(metadata_name)
        if actual is None:
            errors.append(f"public audit log is missing {metadata_name}")
            continue
        if metadata_name == "public-audit-no-overwrite":
            validate_metadata_value(label, actual, parse_binary_setting, errors)
        elif metadata_name == "public-audit-min-parity":
            validate_metadata_value(label, actual, parse_min_parity, errors)
        elif metadata_name == "public-audit-bench-files":
            validate_metadata_value(label, actual, parse_bench_files, errors)
        elif metadata_name == "public-audit-crates-install-script":
            validate_metadata_value(label, actual, parse_crates_install_script, errors)
        if actual != expected:
            errors.append(f"public audit {label} must be {expected}, got {actual}")

    summaries = [SUMMARY_RE.fullmatch(line) for line in text.splitlines()]
    summaries = [match for match in summaries if match is not None]
    if not summaries:
        errors.append("public audit log is missing the public install summary")
    elif len(summaries) > 1:
        errors.append("public audit log must contain exactly one public install summary")
    else:
        summary = summaries[0]
        passed_items = parse_items(summary.group("passed"))
        allowed_missing_items = parse_items(summary.group("allowed_missing"))
        failed_items = parse_items(summary.group("failed"))
        passed = set(passed_items)
        allowed_missing = set(allowed_missing_items)
        failed = set(failed_items)
        summary_counts = Counter(passed_items + allowed_missing_items + failed_items)
        covered = passed | allowed_missing | failed

        for channel, count in sorted(summary_counts.items()):
            if count > 1:
                errors.append(
                    "public audit summary must account for each channel once, "
                    f"got {channel} {count} times"
                )
        if covered != expected_channels:
            errors.append(
                "public audit channels must be "
                f"{sorted(expected_channels)}, got {sorted(covered)}"
            )
        if allowed_missing:
            if allowed_missing - {"crates"}:
                errors.append(
                    "public audit may only allow missing crates, got "
                    f"{sorted(allowed_missing)}"
                )
            if not args.allow_missing_crates:
                errors.append(
                    f"strict public audit must not allow missing channels: {sorted(allowed_missing)}"
                )
        if args.allow_missing_crates and "crates" in expected_channels:
            if "crates" not in passed and "crates" not in allowed_missing and "crates" not in failed:
                errors.append("public audit log does not account for crates")
        if failed:
            errors.append(f"strict public audit has failed channels: {sorted(failed)}")

    exit_codes = re.findall(r"(?m)^public-audit-exit-code=(\d+)$", text)
    if not exit_codes:
        errors.append("public audit log is missing public-audit-exit-code")
    elif len(exit_codes) > 1:
        errors.append("public audit log must contain exactly one public-audit-exit-code")
    elif exit_codes[0] != "0":
        errors.append(f"public audit exit code must be 0, got {exit_codes[0]}")

    observed_channel_sections = re.findall(r"(?m)^>> public install: (.+)$", text)
    unexpected_channel_sections = set(observed_channel_sections) - expected_channels
    for channel in sorted(unexpected_channel_sections):
        errors.append(f"public audit log has unexpected channel section: {channel}")

    observed_expected_channel_sections = [
        channel for channel in observed_channel_sections if channel in expected_channels
    ]
    if observed_expected_channel_sections != expected_channel_order:
        errors.append(
            "public audit channel sections must be in order "
            f"{expected_channel_order}, got {observed_expected_channel_sections}"
        )

    for channel in sorted(expected_channels):
        section_count = len(re.findall(rf"(?m)^>> public install: {re.escape(channel)}$", text))
        if section_count == 0:
            errors.append(f"public audit log is missing channel section: {channel}")
        elif section_count > 1:
            errors.append(f"public audit log has duplicate channel section: {channel}")

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    if args.allow_missing_crates:
        print("verified public audit log with allowed missing crates")
    else:
        print("verified strict public audit log")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
