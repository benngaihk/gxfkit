#!/usr/bin/env python3
"""Check crates.io-facing Cargo metadata for both workspace crates."""
from __future__ import annotations

import os
import re
import sys
import tomllib
from pathlib import Path
from typing import Any


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()
WORKSPACE_CRATES = {
    "gxfkit-core": ROOT / "crates" / "gxfkit-core",
    "gxfkit": ROOT / "crates" / "gxfkit",
}
INHERITED_FIELDS = (
    "version",
    "edition",
    "license",
    "repository",
    "homepage",
    "keywords",
    "categories",
)


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def workspace_field(value: Any) -> bool:
    return isinstance(value, dict) and value.get("workspace") is True


def add(errors: list[str], path: Path, message: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {message}")


def require_file(errors: list[str], path: Path, message: str) -> None:
    if not path.is_file():
        add(errors, path, message)


def check_workspace(root: dict[str, Any], errors: list[str]) -> str | None:
    workspace = root.get("workspace")
    if not isinstance(workspace, dict):
        errors.append("Cargo.toml: missing [workspace]")
        return None

    package = workspace.get("package")
    if not isinstance(package, dict):
        errors.append("Cargo.toml: missing [workspace.package]")
        return None

    version = package.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        errors.append("Cargo.toml: workspace package version must be X.Y.Z")
    if package.get("edition") != "2021":
        errors.append("Cargo.toml: workspace package edition must be 2021")
    if package.get("license") != "MIT":
        errors.append("Cargo.toml: workspace package license must be MIT")
    for field in ("repository", "homepage"):
        value = package.get(field)
        if value != "https://github.com/benngaihk/gxfkit":
            errors.append(f"Cargo.toml: workspace package {field} must point to the GitHub repo")
    authors = package.get("authors")
    if not isinstance(authors, list) or not authors:
        errors.append("Cargo.toml: workspace package authors must be non-empty")
    keywords = package.get("keywords")
    if not isinstance(keywords, list) or not (1 <= len(keywords) <= 5):
        errors.append("Cargo.toml: workspace package keywords must contain 1 to 5 entries")
    elif len(set(keywords)) != len(keywords) or not all(isinstance(item, str) and item for item in keywords):
        errors.append("Cargo.toml: workspace package keywords must be unique non-empty strings")
    categories = package.get("categories")
    if not isinstance(categories, list) or not (1 <= len(categories) <= 5):
        errors.append("Cargo.toml: workspace package categories must contain 1 to 5 entries")
    elif len(set(categories)) != len(categories) or not all(isinstance(item, str) and item for item in categories):
        errors.append("Cargo.toml: workspace package categories must be unique non-empty strings")

    members = workspace.get("members")
    if members != ["crates/gxfkit-core", "crates/gxfkit"]:
        errors.append("Cargo.toml: workspace members must list gxfkit-core then gxfkit")

    return version if isinstance(version, str) else None


def check_crate(name: str, crate_dir: Path, workspace_version: str | None, errors: list[str]) -> None:
    manifest_path = crate_dir / "Cargo.toml"
    require_file(errors, manifest_path, "missing Cargo.toml")
    require_file(errors, crate_dir / "README.md", "package readme file must exist")
    require_file(errors, crate_dir / "LICENSE", "package license file must exist")
    if not manifest_path.is_file():
        return

    manifest = load_toml(manifest_path)
    package = manifest.get("package")
    if not isinstance(package, dict):
        add(errors, manifest_path, "missing [package]")
        return

    if package.get("name") != name:
        add(errors, manifest_path, f"package name must be {name}")
    for field in INHERITED_FIELDS:
        if not workspace_field(package.get(field)):
            add(errors, manifest_path, f"package {field} must inherit from workspace")

    description = package.get("description")
    if not isinstance(description, str) or not (20 <= len(description) <= 200):
        add(errors, manifest_path, "package description must be 20 to 200 characters")

    expected_docs = f"https://docs.rs/{name}"
    if package.get("documentation") != expected_docs:
        add(errors, manifest_path, f"package documentation must be {expected_docs}")
    if package.get("readme") != "README.md":
        add(errors, manifest_path, "package readme must be README.md")

    readme_text = (crate_dir / "README.md").read_text(encoding="utf-8") if (crate_dir / "README.md").is_file() else ""
    if name not in readme_text:
        add(errors, crate_dir / "README.md", f"README should mention {name}")

    if name == "gxfkit":
        bins = manifest.get("bin")
        if not isinstance(bins, list) or not any(
            item.get("name") == "gxfkit" and item.get("path") == "src/main.rs"
            for item in bins
            if isinstance(item, dict)
        ):
            add(errors, manifest_path, "binary crate must declare [[bin]] gxfkit at src/main.rs")

        deps = manifest.get("dependencies")
        core_dep = deps.get("gxfkit-core") if isinstance(deps, dict) else None
        if not isinstance(core_dep, dict):
            add(errors, manifest_path, "gxfkit must depend on gxfkit-core with version and path")
        else:
            if core_dep.get("path") != "../gxfkit-core":
                add(errors, manifest_path, "gxfkit-core dependency path must be ../gxfkit-core")
            if workspace_version and core_dep.get("version") != workspace_version:
                add(
                    errors,
                    manifest_path,
                    f"gxfkit-core dependency version must match workspace version {workspace_version}",
                )


def main() -> int:
    root_manifest = ROOT / "Cargo.toml"
    if not root_manifest.is_file():
        print(f"ERROR {root_manifest}: missing Cargo.toml", file=sys.stderr)
        return 1
    errors: list[str] = []
    workspace_version = check_workspace(load_toml(root_manifest), errors)
    for name, crate_dir in WORKSPACE_CRATES.items():
        check_crate(name, crate_dir, workspace_version, errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print("verified crates.io metadata")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
