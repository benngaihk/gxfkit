#!/usr/bin/env python3
"""Check install documentation matches the recorded public-channel state."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(os.environ.get("GXFKIT_ROOT", Path(__file__).resolve().parents[1])).resolve()


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require(text: str, needle: str, label: str, errors: list[str]) -> None:
    if compact(needle) not in compact(text):
        errors.append(f"{label} must mention: {needle}")


def crates_unpublished(status: str) -> bool:
    return re.search(r"Crates\.io `gxfkit [^`]+` is not published", status) is not None


def crates_published(status: str) -> bool:
    return re.search(r"Current public Crates\.io: `[^`]+`", status) is not None


def main() -> int:
    status = read("docs/RELEASE-STATUS.md")
    readme = read("README.md")
    readme_zh = read("README.zh-CN.md")
    errors: list[str] = []

    require(readme, "Published `v0.0.1` archives predate the no-overwrite output guard", "README.md", errors)
    require(readme, "public install audit verifies future releases with no-overwrite", "README.md", errors)
    require(readme_zh, "已发布的 `v0.0.1` 包早于“拒绝覆盖输出文件”保护", "README.zh-CN.md", errors)
    require(readme_zh, "公开安装审计默认会验证 no-overwrite 和核心语料 parity", "README.zh-CN.md", errors)

    require(readme, "conda install -c conda-forge -c bioconda gxfkit", "README.md", errors)
    require(readme_zh, "conda install -c conda-forge -c bioconda gxfkit", "README.zh-CN.md", errors)
    require(readme, "The current public Bioconda package is `0.0.2`", "README.md", errors)
    require(readme, "passed clean install, smoke conversion, and no-overwrite verification", "README.md", errors)
    require(readme, "strict-audit production evidence", "README.md", errors)
    require(readme_zh, "当前公开的 Bioconda 包是 `0.0.2`", "README.zh-CN.md", errors)
    require(readme_zh, "已通过干净安装、smoke 转换和拒绝覆盖验证", "README.zh-CN.md", errors)
    require(readme_zh, "严格生产证据", "README.zh-CN.md", errors)

    if crates_unpublished(status):
        require(readme, "Once published to Crates.io:", "README.md", errors)
        require(readme, "cargo install gxfkit", "README.md", errors)
        require(readme, "Crates.io is not a current public channel", "README.md", errors)
        require(readme, "do not treat `cargo install gxfkit` as a production install path", "README.md", errors)
        require(readme_zh, "### 计划中的分发方式", "README.zh-CN.md", errors)
        require(readme_zh, "Crates.io：`cargo install gxfkit`", "README.zh-CN.md", errors)
        require(
            readme_zh,
            "这些入口在正式发布前不应写进生产文档作为已可用渠道",
            "README.zh-CN.md",
            errors,
        )
    elif crates_published(status):
        require(readme, "The current public Crates.io package is `0.0.2`", "README.md", errors)
        require(readme, "cargo install gxfkit", "README.md", errors)
        require(readme, "Crates.io has passed clean install, smoke conversion, and no-overwrite verification", "README.md", errors)
        require(readme, "GitHub Release, Bioconda, and Crates.io as production install channels", "README.md", errors)
        require(readme_zh, "### Crates.io", "README.zh-CN.md", errors)
        require(readme_zh, "当前公开的 Crates.io 包是 `0.0.2`", "README.zh-CN.md", errors)
        require(readme_zh, "cargo install gxfkit", "README.zh-CN.md", errors)
        require(readme_zh, "Crates.io 已通过干净安装、smoke 转换和拒绝覆盖验证", "README.zh-CN.md", errors)

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print("verified install docs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
