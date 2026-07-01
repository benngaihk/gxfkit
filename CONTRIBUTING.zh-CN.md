# 贡献指南

[English](CONTRIBUTING.md) | 简体中文

感谢你帮助 `gxfkit` 变得更快、更稳、更可信。

本项目的原则很保守：AGAT 是正确性基准。任何会改变输出的改动，都需要被 AGAT
parity 测试验证；如果差异被接受，也必须记录在 [docs/PARITY.md](docs/PARITY.md)。

## 开发环境

常规检查：

```bash
cargo test --all
cargo clippy --all-targets -- -D warnings
cargo fmt --all -- --check
```

Windows + MSVC 工具链如果缺少 Windows SDK import libs，请使用：

```powershell
powershell -File scripts/with-msvc-env.ps1 cargo test
```

## 修改转换逻辑时

如果你改了 `crates/gxfkit-core/src/convert.rs`、解析器、属性序列化，或者任何可能影响
GTF/GFF 输出的代码，请跑 parity 流程：

```bash
bash corpus/download.sh core
bash benchmark/run.sh
```

如果 AGAT 和 `gxfkit` 输出不同：

1. 确认差异在 `tests/parity/normalize.py` 标准化后仍然存在。
2. 能写小单测就补一个聚焦单测。
3. 如果差异被接受而不是修复，更新 [docs/PARITY.md](docs/PARITY.md)。

不要因为某个输出“看起来更干净”就静默偏离 AGAT。这个项目的价值来自可验证的兼容性。

## 提交 Issue

中文 Issue 欢迎使用。为了方便维护，请尽量选择对应模板：

- Bug：崩溃、错误提示、CLI 行为异常。
- 功能请求：新的 AGAT 命令、格式边界、流程集成。
- AGAT parity divergence：同一输入下，AGAT 与 `gxfkit` 输出不同。

提交 parity 问题时，最好包含：

- AGAT 版本。
- `gxfkit` 版本。
- 两边完整命令。
- 最小 GFF/GTF 输入片段，或公开数据链接。
- 标准化后的 diff。

## 发布前检查

维护者切 release 前应运行：

```bash
bash scripts/release-check.sh
```

发布流程会构建跨平台 archive 并做 smoke test。分发状态以 README 和 release notes
为准，不要在文档里把尚未发布的 Bioconda/Crates.io/PyPI 渠道写成已可用。
