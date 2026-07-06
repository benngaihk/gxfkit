#!/usr/bin/env python3
"""Compute the sha256 for the GitHub source archive used by Bioconda."""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path


VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
CURL_TIMEOUT_ARGS = (
    "--retry",
    "3",
    "--retry-delay",
    "2",
    "--retry-max-time",
    "60",
    "--connect-timeout",
    "10",
    "--max-time",
    "30",
)


def default_url(version: str) -> str:
    return f"https://github.com/benngaihk/gxfkit/archive/refs/tags/v{version}.tar.gz"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme in ("", "file"):
        path = Path(urllib.request.url2pathname(parsed.path if parsed.scheme else url))
        return sha256_file(path)

    digest = hashlib.sha256()
    try:
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "gxfkit-github-source-sha256"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
        return digest.hexdigest()
    except Exception as first_error:  # noqa: BLE001 - fallback keeps macOS cert issues from blocking release prep.
        if not shutil.which("curl"):
            raise RuntimeError(f"download failed and curl is not installed: {first_error}") from first_error

    proc = subprocess.Popen(
        [
            "curl",
            "-fsSL",
            *CURL_TIMEOUT_ARGS,
            "-H",
            "User-Agent: gxfkit-github-source-sha256",
            url,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.stdout is not None
    while chunk := proc.stdout.read(1024 * 1024):
        digest.update(chunk)
    _, stderr = proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError(stderr.decode(errors="replace").strip() or f"curl exited {proc.returncode}")
    return digest.hexdigest()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="release version without leading v, for example 0.0.2")
    parser.add_argument("--url", help="override archive URL; mainly for tests")
    parser.add_argument(
        "--format",
        choices=("plain", "prepare-command"),
        default="plain",
        help="output sha only, or the prepare-next-version command",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not VERSION_RE.fullmatch(args.version):
        print(f"ERROR invalid version: {args.version}", file=sys.stderr)
        return 2
    url = args.url or default_url(args.version)
    try:
        digest = sha256_url(url)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR failed to compute sha256 for {url}: {exc}", file=sys.stderr)
        return 1

    if args.format == "prepare-command":
        print(f"python3 scripts/prepare-next-version.py {args.version} --bioconda-sha256 {digest}")
    else:
        print(digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
