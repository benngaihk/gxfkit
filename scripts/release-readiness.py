#!/usr/bin/env python3
"""Report whether the current tree is ready for tag or public-release closure."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
REPO = "benngaihk/gxfkit"
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
STRICT_PUBLIC_AUDIT_ENV = {
    "VERIFY_PUBLIC_INSTALL_CHANNELS": "github-linux github-parity bioconda crates",
    "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES": "0",
    "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE": "1",
    "VERIFY_PUBLIC_INSTALLS_MIN_PARITY": "100",
    "BENCH_FILES": "human_chr1 human_chr21 yeast",
}
RELEASE_PACKAGES = (
    "linux-x86_64-static",
    "linux-aarch64-static",
    "macos-x86_64",
    "macos-aarch64",
)
BIOCONDA_SUBDIRS = ("linux-64", "osx-64")


@dataclass
class Result:
    status: str
    name: str
    detail: str


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def run(cmd: list[str], *, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def github_auth_header(url: str) -> list[str]:
    if not url.startswith("https://api.github.com/"):
        return []
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token is None and shutil.which("gh"):
        proc = subprocess.run(
            ["gh", "auth", "token"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if proc.returncode == 0:
            token = proc.stdout.strip()
    if not token:
        return []
    return ["-H", f"Authorization: Bearer {token}"]


def git(*args: str) -> str | None:
    proc = run(["git", *args])
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def fetch_json(url: str) -> dict[str, Any]:
    if shutil.which("curl"):
        proc = run(
            [
                "curl",
                "-fsSL",
                *CURL_TIMEOUT_ARGS,
                "-H",
                "Accept: application/json",
                "-H",
                "User-Agent: gxfkit-release-readiness",
                *github_auth_header(url),
                url,
            ]
        )
        if proc.returncode == 0:
            return json.loads(proc.stdout)
        raise RuntimeError(proc.stderr.strip() or f"curl failed for {url}")

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "gxfkit-release-readiness",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_text(url: str) -> str:
    if shutil.which("curl"):
        proc = run(
            [
                "curl",
                "-fsSL",
                *CURL_TIMEOUT_ARGS,
                "-H",
                "User-Agent: gxfkit-release-readiness",
                url,
            ]
        )
        if proc.returncode == 0:
            return proc.stdout
        raise RuntimeError(proc.stderr.strip() or f"curl failed for {url}")

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "gxfkit-release-readiness"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read().decode("utf-8")


def workspace_version() -> str:
    root = load_toml(ROOT / "Cargo.toml")
    version = root.get("workspace", {}).get("package", {}).get("version")
    if not isinstance(version, str):
        raise RuntimeError("missing workspace.package.version in Cargo.toml")
    return version


def bioconda_version() -> str | None:
    path = ROOT / "packaging" / "bioconda" / "recipe" / "meta.yaml"
    if not path.is_file():
        return None
    match = re.search(r'{% set version = "([^"]+)" %}', path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def cargo_dependency_version() -> str | None:
    manifest = load_toml(ROOT / "crates" / "gxfkit" / "Cargo.toml")
    dep = manifest.get("dependencies", {}).get("gxfkit-core")
    if not isinstance(dep, dict):
        return None
    version = dep.get("version")
    return version if isinstance(version, str) else None


def cargo_versions_from_ref(ref: str) -> tuple[str | None, str | None]:
    root_text = git("show", f"{ref}:Cargo.toml")
    cli_text = git("show", f"{ref}:crates/gxfkit/Cargo.toml")
    if root_text is None or cli_text is None:
        return (None, None)
    try:
        root_manifest = tomllib.loads(root_text)
        cli_manifest = tomllib.loads(cli_text)
    except tomllib.TOMLDecodeError:
        return (None, None)
    version = root_manifest.get("workspace", {}).get("package", {}).get("version")
    dep = cli_manifest.get("dependencies", {}).get("gxfkit-core")
    dep_version = dep.get("version") if isinstance(dep, dict) else None
    return (
        version if isinstance(version, str) else None,
        dep_version if isinstance(dep_version, str) else None,
    )


def result(status: str, name: str, detail: str) -> Result:
    return Result(status=status, name=name, detail=detail)


def strict_public_audit_command(version: str, tag: str) -> str:
    env = " ".join(
        f"{key}={value!r}"
        for key, value in {
            **STRICT_PUBLIC_AUDIT_ENV,
            "VERSION": version,
            "RELEASE_TAG": tag,
        }.items()
    )
    return f"{env} bash scripts/verify-public-installs.sh"


def strict_public_closure_command(version: str) -> str:
    return (
        "python3 scripts/release-readiness.py "
        f"--phase public --version {version} --check-public --run-public-audit"
    )


def public_channel_discovery_command(version: str) -> str:
    return f"python3 scripts/release-readiness.py --phase public --version {version} --check-public"


def command_check(name: str, cmd: list[str], success_detail: str) -> Result:
    proc = run(cmd)
    if proc.returncode == 0:
        return result("PASS", name, success_detail)
    tail = detail_tail(proc.stdout + proc.stderr, proc.returncode)
    return result("FAIL", name, tail)


def detail_tail(text: str, returncode: int) -> str:
    details = text.strip().splitlines()
    return "; ".join(details[-3:]) if details else f"exit {returncode}"


def check_benchmark_summary() -> Result:
    proc = run(["python3", "scripts/check-benchmark-summary.py"])
    detail_lines = (proc.stdout + proc.stderr).strip().splitlines()
    detail = detail_lines[-1] if detail_lines else f"exit {proc.returncode}"
    if proc.returncode != 0:
        return result("FAIL", "benchmark summary", detail)
    if detail.startswith("benchmark summary not found;"):
        return result("WARN", "benchmark summary", detail)
    return result("PASS", "benchmark summary", detail)


def check_local_tag_guards(version: str) -> list[Result]:
    return [
        command_check(
            "release notes",
            ["python3", "scripts/check-release-notes.py", "--expected-version", version],
            f"docs/releases/v{version}.md is ready",
        ),
        command_check(
            "maintainer surfaces",
            ["python3", "scripts/check-maintainer-surfaces.py"],
            "templates and workflow prompts match workspace version",
        ),
        command_check(
            "workflow policy",
            ["python3", "scripts/check-workflow-policy.py"],
            "GitHub Actions workflows declare permissions and job timeouts",
        ),
        command_check(
            "workflow contracts",
            [
                "bash",
                "-c",
                "bash scripts/test-ci-workflow.sh && "
                "bash scripts/test-release-workflow.sh && "
                "bash scripts/test-publish-crates-workflow.sh && "
                "bash scripts/test-public-install-audit-workflow.sh",
            ],
            "CI, release, publish, and public-audit workflows match release automation",
        ),
        command_check(
            "release artifacts",
            ["python3", "scripts/check-release-artifacts.py"],
            "release archive names, checksums, uploads, and verifier contract match",
        ),
        command_check(
            "crate metadata",
            ["python3", "scripts/check-crate-metadata.py"],
            "crates.io package metadata is complete",
        ),
        command_check(
            "package file lists",
            ["bash", "scripts/check-package-files.sh"],
            "locked crate packages include Cargo.toml, README.md, LICENSE, and source entrypoints",
        ),
        command_check(
            "version consistency",
            [
                "bash",
                "-c",
                "python3 scripts/check-version-consistency.py "
                f"--scope cargo --expected-version {version} && "
                "python3 scripts/check-version-consistency.py --scope bioconda",
            ],
            "Cargo release metadata matches target and Bioconda metadata is internally consistent",
        ),
        command_check(
            "bioconda recipe",
            ["python3", "scripts/check-bioconda-recipe.py"],
            "Bioconda recipe and template are structurally valid",
        ),
        check_benchmark_summary(),
        command_check(
            "release status doc",
            ["python3", "scripts/check-release-status-doc.py"],
            "docs/RELEASE-STATUS.md matches release boundary",
        ),
        command_check(
            "install docs",
            ["python3", "scripts/check-install-docs.py"],
            "README install sections match public-channel state",
        ),
        command_check(
            "release guide",
            ["python3", "scripts/check-release-doc.py"],
            "docs/RELEASE.md matches release automation",
        ),
        command_check(
            "release-check contract",
            ["python3", "scripts/check-release-check.py"],
            "scripts/release-check.sh keeps deterministic local preflight behavior",
        ),
        command_check(
            "parity doc",
            ["python3", "scripts/check-parity-doc.py"],
            "docs/PARITY.md matches release parity gate",
        ),
        command_check(
            "shell syntax",
            ["bash", "scripts/test-shell-syntax.sh"],
            "repository shell scripts parse",
        ),
        command_check(
            "python syntax",
            ["python3", "scripts/test-python-syntax.py"],
            "repository Python scripts parse",
        ),
        command_check(
            "repo hygiene",
            ["bash", "scripts/test-repo-hygiene.sh"],
            "generated cache/evidence artifacts are ignored",
        ),
        command_check(
            "executable scripts",
            ["bash", "scripts/test-executable-scripts.sh"],
            "directly invoked scripts are executable",
        ),
    ]


def check_source_candidate(
    version: str,
    allow_dirty: bool,
    source_version: str | None = None,
    *,
    phase: str = "tag",
) -> list[Result]:
    checks: list[Result] = []
    actual_source_version = source_version or version
    dep_version = cargo_dependency_version()
    if actual_source_version == version and dep_version == version:
        checks.append(result("PASS", "cargo versions", f"workspace and gxfkit-core dependency are {version}"))
    else:
        checks.append(
            result(
                "FAIL",
                "cargo versions",
                f"target is {version}, workspace is {actual_source_version}, "
                f"gxfkit-core dependency is {dep_version or '<missing>'}",
            )
        )

    status = git("status", "--porcelain")
    if status is None:
        checks.append(result("FAIL", "git worktree", "not a git repository"))
    elif status:
        state = "WARN" if allow_dirty else "PENDING"
        detail = "worktree has uncommitted changes"
        if allow_dirty:
            detail += " (--allow-dirty)"
        checks.append(result(state, "git worktree", detail))
    else:
        checks.append(result("PASS", "git worktree", "clean"))

    tag = f"v{version}"
    head = git("rev-parse", "HEAD")
    tagged = git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}")
    if tagged is None:
        checks.append(result("PASS", "publish ref", f"{tag} does not exist yet"))
    elif head == tagged:
        checks.append(result("PASS", "publish ref", f"HEAD matches {tag}"))
    elif phase == "public":
        tag_version, tag_dep_version = cargo_versions_from_ref(tag)
        if tag_version == version and tag_dep_version == version:
            checks.append(
                result(
                    "PASS",
                    "publish ref",
                    f"{tag} points at release commit {tagged[:12]}; publish Crates.io from {tag}",
                )
            )
        else:
            checks.append(
                result(
                    "FAIL",
                    "publish ref",
                    f"{tag} cargo metadata mismatch: workspace={tag_version or '<missing>'}, "
                    f"gxfkit-core dependency={tag_dep_version or '<missing>'}",
                )
            )
    else:
        checks.append(result("FAIL", "publish ref", f"{tag} points at a different commit"))

    bio_version = bioconda_version()
    if bio_version == version:
        checks.append(result("PASS", "bioconda metadata", f"recipe is already {version}"))
    elif bio_version:
        checks.append(
            result(
                "WARN",
                "bioconda metadata",
                f"recipe is {bio_version}; this is allowed before {tag} source sha256 exists",
            )
        )
    else:
        checks.append(result("WARN", "bioconda metadata", "recipe version not found"))

    checks.extend(check_local_tag_guards(version))

    return checks


def public_crate_state(crate: str, version: str) -> tuple[str, str]:
    data = fetch_json(f"https://crates.io/api/v1/crates/{crate}")
    versions = data.get("versions")
    if not isinstance(versions, list):
        return ("invalid", f"invalid metadata: versions={versions!r}")
    for item in versions:
        if isinstance(item, dict) and item.get("num") == version:
            yanked = item.get("yanked")
            if yanked is True:
                return ("yanked", f"{version} is yanked")
            checksum = item.get("checksum")
            crate_size = item.get("crate_size")
            invalid: list[str] = []
            if yanked is not False:
                invalid.append(f"yanked={yanked!r}")
            if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
                invalid.append(f"checksum={checksum!r}")
            if not isinstance(crate_size, int) or crate_size <= 0:
                invalid.append(f"crate_size={crate_size!r}")
            if invalid:
                return ("invalid", "invalid metadata: " + "; ".join(invalid))
            return ("available", f"{version} is available with checksum and non-zero crate size")
    return ("missing", f"{version} is not available")


def missing_public_resource(exc: Exception) -> bool:
    text = str(exc)
    return "404" in text or "Not Found" in text


def access_limited_public_resource(exc: Exception) -> bool:
    text = str(exc).lower()
    return "403" in text or "forbidden" in text or "rate limit" in text


def pending_public_resource_detail(name: str, exc: Exception) -> str | None:
    if missing_public_resource(exc):
        return f"{name} not available"
    if access_limited_public_resource(exc):
        return f"{name} not available or access limited"
    return None


def expected_release_assets(tag: str) -> set[str]:
    assets: set[str] = set()
    for package in RELEASE_PACKAGES:
        archive = f"gxfkit-{tag}-{package}.tar.gz"
        assets.add(archive)
        assets.add(f"{archive}.sha256")
    return assets


def expected_release_asset_url(tag: str, name: str) -> str:
    return f"https://github.com/{REPO}/releases/download/{tag}/{name}"


def release_checksum_status(name: str, url: str) -> tuple[str, str, str | None]:
    target = name.removesuffix(".sha256")
    try:
        text = fetch_text(url)
    except Exception as exc:  # noqa: BLE001
        detail = pending_public_resource_detail(name, exc)
        if detail is not None:
            return ("PENDING", f"{name} fetch pending: {detail}", None)
        return ("FAIL", f"{name} fetch failed: {exc}", None)

    lines = text.splitlines()
    if len(lines) != 1:
        return ("FAIL", f"{name} must contain exactly one line", None)
    match = re.fullmatch(r"([0-9a-f]{64})[ \t]+(\S+)", lines[0])
    if not match:
        return ("FAIL", f"{name} has invalid checksum line", None)
    checksum = match.group(1)
    checksum_target = match.group(2)
    if checksum_target != target:
        return ("FAIL", f"{name} verifies {checksum_target!r}, expected {target!r}", None)
    return ("PASS", "", checksum)


def check_github_release_tag_commit(tag: str) -> Result:
    try:
        commit = fetch_json(f"https://api.github.com/repos/{REPO}/commits/{tag}")
    except urllib.error.HTTPError as exc:
        detail = pending_public_resource_detail(f"{tag} commit", exc)
        if detail is not None:
            return result("PENDING", "GitHub release tag commit", f"{detail} ({exc.code})")
        return result("FAIL", "GitHub release tag commit", f"check failed: {exc}")
    except Exception as exc:  # noqa: BLE001
        detail = pending_public_resource_detail(f"{tag} commit", exc)
        if detail is not None:
            return result("PENDING", "GitHub release tag commit", detail)
        return result("FAIL", "GitHub release tag commit", f"check failed: {exc}")

    remote_sha = commit.get("sha")
    if not isinstance(remote_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", remote_sha):
        return result("FAIL", "GitHub release tag commit", f"invalid sha={remote_sha!r}")

    local_sha = git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}")
    if local_sha:
        if local_sha == remote_sha:
            return result("PASS", "GitHub release tag commit", f"{tag} resolves to local tag commit {remote_sha[:12]}")
        return result(
            "FAIL",
            "GitHub release tag commit",
            f"{tag} remote {remote_sha[:12]} != local {local_sha[:12]}",
        )
    return result("PASS", "GitHub release tag commit", f"{tag} resolves to {remote_sha[:12]}")


def bioconda_file_invalid_reasons(item: dict[str, Any], version: str, subdir: str) -> list[str]:
    basename = item.get("basename")
    labels = item.get("labels", [])
    sha256 = item.get("sha256")
    size = item.get("size")
    invalid: list[str] = []
    if not isinstance(basename, str) or not basename.startswith(f"{subdir}/gxfkit-{version}-"):
        invalid.append(f"{subdir} basename={basename!r}")
    elif not (basename.endswith(".conda") or basename.endswith(".tar.bz2")):
        invalid.append(f"{subdir} basename={basename!r}")
    elif not re.fullmatch(
        rf"{re.escape(subdir)}/gxfkit-{re.escape(version)}-[A-Za-z0-9_.-]+_0[.](conda|tar[.]bz2)",
        basename,
    ):
        invalid.append(f"{subdir} build_number basename={basename!r}")
    if "main" not in labels:
        invalid.append(f"{subdir} labels={labels!r}")
    if "broken" in labels:
        invalid.append(f"{subdir} labels={labels!r}")
    if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", sha256):
        invalid.append(f"{subdir} sha256={sha256!r}")
    if not isinstance(size, int) or size <= 0:
        invalid.append(f"{subdir} size={size!r}")
    return invalid


def check_bioconda_public(data: dict[str, Any], version: str) -> list[Result]:
    checks: list[Result] = []
    versions = data.get("versions")
    if not isinstance(versions, list):
        return [result("FAIL", "Bioconda package metadata", f"invalid metadata: versions={versions!r}")]
    if version not in versions:
        return [result("PENDING", "Bioconda package metadata", f"available versions: {versions}")]

    checks.append(result("PASS", "Bioconda package metadata", f"gxfkit {version} files are listed"))
    files = data.get("files")
    if not isinstance(files, list):
        checks.append(result("FAIL", "Bioconda package files", f"invalid metadata: files={files!r}"))
        return checks
    files_by_subdir: dict[str, list[dict[str, Any]]] = {}
    for item in files:
        if not isinstance(item, dict) or item.get("version") != version:
            continue
        attrs = item.get("attrs", {})
        subdir = attrs.get("subdir") if isinstance(attrs, dict) else None
        if not isinstance(subdir, str):
            basename = item.get("basename")
            if isinstance(basename, str) and "/" in basename:
                subdir = basename.split("/", 1)[0]
        if isinstance(subdir, str) and subdir in BIOCONDA_SUBDIRS:
            files_by_subdir.setdefault(subdir, []).append(item)

    missing = [subdir for subdir in BIOCONDA_SUBDIRS if subdir not in files_by_subdir]
    if missing:
        checks.append(result("FAIL", "Bioconda package files", "missing subdir(s): " + ", ".join(missing)))
        return checks

    invalid: list[str] = []
    for subdir in BIOCONDA_SUBDIRS:
        candidate_errors = [
            bioconda_file_invalid_reasons(item, version, subdir)
            for item in files_by_subdir[subdir]
        ]
        if any(not errors for errors in candidate_errors):
            continue
        invalid.extend(candidate_errors[0])

    if invalid:
        checks.append(result("FAIL", "Bioconda package files", "invalid: " + "; ".join(invalid)))
    else:
        checks.append(
            result(
                "PASS",
                "Bioconda package files",
                "main linux-64 and osx-64 build 0 packages are present with sha256 and non-zero size",
            )
        )
    return checks


def check_public_channels(version: str, tag: str) -> list[Result]:
    checks: list[Result] = []
    try:
        release = fetch_json(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}")
        if release.get("tag_name") == tag:
            if release.get("draft") is True:
                checks.append(result("FAIL", "GitHub release", f"{tag} is still a draft"))
            elif release.get("prerelease") is True:
                checks.append(result("FAIL", "GitHub release", f"{tag} is marked as prerelease"))
            else:
                checks.append(result("PASS", "GitHub release", f"{tag} exists"))
            asset_items = [
                asset
                for asset in release.get("assets", [])
                if isinstance(asset, dict) and isinstance(asset.get("name"), str)
            ]
            asset_names = [asset["name"] for asset in asset_items]
            duplicate_assets = sorted(
                name for name in set(asset_names) if asset_names.count(name) > 1
            )
            assets_by_name = {asset["name"]: asset for asset in asset_items}
            expected_assets = expected_release_assets(tag)
            missing_assets = sorted(expected_assets - set(assets_by_name))
            unexpected_package_assets = sorted(
                name
                for name in assets_by_name
                if name.startswith(f"gxfkit-{tag}-")
                and name.endswith((".tar.gz", ".tar.gz.sha256"))
                and name not in expected_assets
            )
            if duplicate_assets:
                checks.append(
                    result(
                        "FAIL",
                        "GitHub release assets",
                        "duplicate asset name(s): " + ", ".join(duplicate_assets),
                    )
                )
            elif missing_assets:
                checks.append(
                    result(
                        "FAIL",
                        "GitHub release assets",
                        "missing: " + ", ".join(missing_assets),
                    )
                )
            elif unexpected_package_assets:
                checks.append(
                    result(
                        "FAIL",
                        "GitHub release assets",
                        "unexpected package asset(s): " + ", ".join(unexpected_package_assets),
                    )
                )
            else:
                invalid_assets: list[str] = []
                for name in sorted(expected_assets):
                    asset = assets_by_name[name]
                    state = asset.get("state")
                    size = asset.get("size")
                    browser_download_url = asset.get("browser_download_url")
                    if state != "uploaded" or not isinstance(size, int) or size <= 0:
                        invalid_assets.append(f"{name} state={state or '<missing>'} size={size!r}")
                    if browser_download_url != expected_release_asset_url(tag, name):
                        invalid_assets.append(f"{name} browser_download_url={browser_download_url!r}")
                if invalid_assets:
                    checks.append(
                        result(
                            "FAIL",
                            "GitHub release assets",
                            "invalid: " + "; ".join(invalid_assets),
                        )
                    )
                else:
                    invalid_checksums: list[str] = []
                    pending_checksums: list[str] = []
                    checksum_digests: dict[str, list[str]] = {}
                    for name in sorted(expected_assets):
                        if not name.endswith(".sha256"):
                            continue
                        status, reason, digest = release_checksum_status(
                            name,
                            expected_release_asset_url(tag, name),
                        )
                        if status == "PENDING":
                            pending_checksums.append(reason)
                        elif status == "FAIL":
                            invalid_checksums.append(reason)
                        elif digest is not None:
                            checksum_digests.setdefault(digest, []).append(name)
                    duplicate_digests = [
                        names for names in checksum_digests.values() if len(names) > 1
                    ]
                    for names in duplicate_digests:
                        invalid_checksums.append(
                            "duplicate checksum digest for " + ", ".join(sorted(names))
                        )
                    checks.append(
                        result(
                            "PASS",
                            "GitHub release assets",
                            f"{len(expected_assets)} expected asset(s) are uploaded, non-empty, and downloadable",
                        )
                    )
                    if invalid_checksums:
                        checks.append(
                            result(
                                "FAIL",
                                "GitHub release checksums",
                                "invalid: " + "; ".join(invalid_checksums),
                            )
                        )
                    elif pending_checksums:
                        checks.append(
                            result(
                                "PENDING",
                                "GitHub release checksums",
                                "pending: " + "; ".join(pending_checksums),
                            )
                        )
                    else:
                        checks.append(
                            result(
                                "PASS",
                                "GitHub release checksums",
                                "4 checksum asset(s) point at matching archives with unique digests",
                            )
                        )
            checks.append(check_github_release_tag_commit(tag))
        else:
            checks.append(result("FAIL", "GitHub release", f"unexpected release response for {tag}"))
    except urllib.error.HTTPError as exc:
        detail = pending_public_resource_detail(tag, exc)
        if detail is not None:
            checks.append(result("PENDING", "GitHub release", f"{detail} ({exc.code})"))
        else:
            checks.append(result("FAIL", "GitHub release", f"check failed: {exc}"))
    except Exception as exc:  # noqa: BLE001 - report network diagnostics without traceback noise.
        detail = pending_public_resource_detail(tag, exc)
        if detail is not None:
            checks.append(result("PENDING", "GitHub release", detail))
        else:
            checks.append(result("FAIL", "GitHub release", f"check failed: {exc}"))

    try:
        data = fetch_json("https://api.anaconda.org/package/bioconda/gxfkit")
        checks.extend(check_bioconda_public(data, version))
    except Exception as exc:  # noqa: BLE001
        detail = pending_public_resource_detail("gxfkit", exc)
        if detail is not None:
            checks.append(result("PENDING", "Bioconda package metadata", detail))
        else:
            checks.append(result("FAIL", "Bioconda package metadata", f"check failed: {exc}"))

    for crate in ("gxfkit-core", "gxfkit"):
        try:
            crate_state, crate_detail = public_crate_state(crate, version)
            if crate_state == "available":
                checks.append(result("PASS", f"Crates.io {crate}", crate_detail))
            elif crate_state in {"yanked", "invalid"}:
                checks.append(result("FAIL", f"Crates.io {crate}", crate_detail))
            else:
                checks.append(result("PENDING", f"Crates.io {crate}", crate_detail))
        except urllib.error.HTTPError as exc:
            detail = pending_public_resource_detail(f"{crate} {version}", exc)
            if detail is not None:
                checks.append(result("PENDING", f"Crates.io {crate}", f"{detail} ({exc.code})"))
            else:
                checks.append(result("FAIL", f"Crates.io {crate}", f"check failed: {exc}"))
        except Exception as exc:  # noqa: BLE001
            detail = pending_public_resource_detail(f"{crate} {version}", exc)
            if detail is not None:
                checks.append(result("PENDING", f"Crates.io {crate}", detail))
            else:
                checks.append(result("FAIL", f"Crates.io {crate}", f"check failed: {exc}"))

    return checks


def run_public_audit(version: str, tag: str) -> Result:
    env = os.environ.copy()
    env.update(STRICT_PUBLIC_AUDIT_ENV)
    env["VERSION"] = version
    env["RELEASE_TAG"] = tag
    proc = subprocess.run(
        ["bash", "scripts/verify-public-installs.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log_text = proc.stdout + f"public-audit-exit-code={proc.returncode}\n"
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "public-audit.log"
        log_path.write_text(log_text, encoding="utf-8")
        verifier = run(
            [
                sys.executable,
                "scripts/check-public-audit-log.py",
                "--version",
                version,
                "--tag",
                tag,
                "--channels",
                STRICT_PUBLIC_AUDIT_ENV["VERIFY_PUBLIC_INSTALL_CHANNELS"],
                "--verify-no-overwrite",
                STRICT_PUBLIC_AUDIT_ENV["VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"],
                "--min-parity",
                STRICT_PUBLIC_AUDIT_ENV["VERIFY_PUBLIC_INSTALLS_MIN_PARITY"],
                "--bench-files",
                STRICT_PUBLIC_AUDIT_ENV["BENCH_FILES"],
                str(log_path),
            ]
        )

    if proc.returncode == 0:
        if verifier.returncode == 0:
            return result("PASS", "strict public audit", "verify-public-installs.sh passed and audit log verified")
        tail = detail_tail(verifier.stdout + verifier.stderr, verifier.returncode)
        return result("FAIL", "strict public audit", f"audit log invalid: {tail}")

    if verifier.returncode != 0:
        tail = detail_tail(verifier.stdout + verifier.stderr, verifier.returncode)
        return result("FAIL", "strict public audit", f"verify-public-installs.sh failed; audit log guard failed: {tail}")

    tail = detail_tail(log_text, proc.returncode)
    return result("FAIL", "strict public audit", f"verify-public-installs.sh failed: {tail}")


def check_public_release(version: str, args: argparse.Namespace, source_version: str) -> list[Result]:
    tag = f"v{version}"
    checks = check_source_candidate(version, args.allow_dirty, source_version, phase="public")

    tagged = git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}")
    head = git("rev-parse", "HEAD")
    if tagged and head == tagged:
        checks.append(result("PASS", "release tag", f"{tag} exists at HEAD"))
    elif tagged:
        tag_version, tag_dep_version = cargo_versions_from_ref(tag)
        if tag_version == version and tag_dep_version == version:
            checks.append(result("PASS", "release tag", f"{tag} exists at release commit {tagged[:12]}"))
        else:
            checks.append(
                result(
                    "FAIL",
                    "release tag",
                    f"{tag} cargo metadata mismatch: workspace={tag_version or '<missing>'}, "
                    f"gxfkit-core dependency={tag_dep_version or '<missing>'}",
                )
            )
    else:
        checks.append(result("PENDING", "release tag", f"{tag} does not exist"))

    bio_version = bioconda_version()
    if bio_version == version:
        checks.append(result("PASS", "bioconda release metadata", f"recipe is {version}"))
    else:
        checks.append(
            result(
                "PENDING",
                "bioconda release metadata",
                f"recipe is {bio_version or '<missing>'}; update after {tag} source sha256 is known",
            )
        )

    if args.check_public:
        checks.extend(check_public_channels(version, tag))
    else:
        detail = f"rerun {public_channel_discovery_command(version)} after publishing"
        if args.run_public_audit:
            detail += "; strict audit does not replace public channel discovery"
        checks.append(
            result(
                "PENDING",
                "public channel discovery",
                detail,
            )
        )

    if args.run_public_audit:
        checks.append(run_public_audit(version, tag))
    else:
        checks.append(
            result(
                "PENDING",
                "strict public audit",
                f"run {strict_public_closure_command(version)} "
                f"(strict audit: {strict_public_audit_command(version, tag)})",
            )
        )

    return checks


def print_checks(version: str, phase: str, checks: list[Result]) -> None:
    print(f"release readiness: version={version} phase={phase}")
    for check in checks:
        print(f"{check.status:7} {check.name}: {check.detail}")
    blockers = [item for item in checks if item.status in {"FAIL", "PENDING"}]
    if blockers:
        print("status: not ready")
    else:
        print("status: ready")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("tag", "public"), default="tag")
    parser.add_argument("--version", help="release version to inspect; defaults to workspace version")
    parser.add_argument("--allow-dirty", action="store_true", help="downgrade dirty worktree to WARN")
    parser.add_argument("--check-public", action="store_true", help="check public GitHub/Bioconda/Crates.io state")
    parser.add_argument("--run-public-audit", action="store_true", help="run the strict public install audit")
    args = parser.parse_args()

    if args.phase == "tag" and (args.check_public or args.run_public_audit):
        parser.error("--check-public and --run-public-audit require --phase public")

    try:
        source_version = workspace_version()
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR failed to read workspace version: {exc}", file=sys.stderr)
        return 2
    version = args.version or source_version
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version):
        print(f"ERROR invalid release version: {version}", file=sys.stderr)
        return 2

    checks = (
        check_source_candidate(version, args.allow_dirty, source_version)
        if args.phase == "tag"
        else check_public_release(version, args, source_version)
    )
    print_checks(version, args.phase, checks)
    return 1 if any(item.status in {"FAIL", "PENDING"} for item in checks) else 0


if __name__ == "__main__":
    raise SystemExit(main())
