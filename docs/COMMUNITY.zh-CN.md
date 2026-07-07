# 中文社区维护指南

这个文档面向 `gxfkit` 维护者，用来保持 GitHub 上的中文内容一致、准确、可维护。

## 目标用户

中文内容优先服务这些用户：

- 高校、医院、公司里的生信分析人员和流程工程师。
- 已经在使用 AGAT，尤其是 `agat_convert_sp_gff2gtf.pl` 的用户。
- 需要处理大 GFF3/GTF 文件，并愿意用 AGAT parity 验证替换风险的用户。

不要把 `gxfkit` 宣传成 AGAT 的完整替代品。当前定位是：**AGAT 兼容的高速子集，
生产路径是 `gff2gtf`，`main` 上的 `gxf2gxf` 是标准化 beta。**

## 中文内容入口

仓库内的中文入口应保持这些文件同步：

- [README.zh-CN.md](../README.zh-CN.md)：给首次访问者看的项目介绍、安装、使用和风险边界。
- [CONTRIBUTING.zh-CN.md](../CONTRIBUTING.zh-CN.md)：给贡献者看的开发和 parity 规则。
- [FAQ.zh-CN.md](FAQ.zh-CN.md)：给用户看的常见问题。
- 中文 Issue 模板：降低中文用户反馈成本。

英文 README 仍然是主入口；中文 README 应跟随英文事实更新，但可以更强调国内用户关心的
安装、HPC、conda、流程替换和数据复现。

## 内容口径

推荐使用这些表达：

- “AGAT 是正确性基准。”
- “当前 alpha 阶段的生产支持路径是 `gff2gtf`。”
- “在核心语料（人类 chr1、人类 chr21、酵母）上，标准化后与 AGAT 100% 一致。”
- “`gxf2gxf` 标准化 beta 已在 `main` 上 fixture-gated，但还不是完整 AGAT 替代品。”
- “已知差异记录在 `docs/PARITY.md`。”
- “GitHub Release、Bioconda 和 Crates.io 的 `0.0.2` 已通过公开安装审计。”
- “当前公开稳定包是 `0.0.2`；`main` 上的 beta 功能需要从源码或 git 安装。”

避免使用这些表达：

- “完全替代 AGAT。”
- “所有 GFF/GTF 都兼容。”
- “无风险替换生产流程。”
- “PyPI 已可安装”，除非对应发布和安装 smoke 已经验证。

## Issue 维护建议

中文 Issue 可以直接用中文回复，但建议保留关键技术词的英文原文，例如：
`AGAT parity`、`gff2gtf`、`GFF3`、`GTF`、`normalized diff`。

处理优先级：

1. **可复现 parity divergence。** 这类 issue 最有价值，优先确认。
2. **真实流程集成问题。** Snakemake、Nextflow、HPC module、container 等。
3. **安装问题。** release archive、权限、PATH、Windows/MSVC。
4. **泛泛的格式支持请求。** 引导用户提供最小输入和对应 AGAT 行为。

回复 parity 问题时，尽量要求用户补充：

- AGAT 版本。
- `gxfkit` 版本。
- 原始命令。
- 最小输入片段。
- 标准化 diff。

## 中文推广内容

适合对外发布的主题：

- `AGAT 太慢？用 Rust 加速 GFF3 到 GTF 转换`
- `gxfkit：一个以 AGAT 输出为基准的高速 GFF/GTF 工具`
- `如何用 AGAT parity 检查替换风险`
- `在 Snakemake/Nextflow/HPC 中试用 gxfkit`
- `gxf2gxf 标准化 beta：邀请真实 GFF3 兼容性反馈`

每篇内容都应该包含：

- 当前支持范围。
- 可复现 benchmark 命令。
- AGAT parity 方法。
- 不建议直接替换的场景。
- GitHub issue 反馈入口。

## Release 中文检查清单

每次发布前检查：

- `README.md` 和 `README.zh-CN.md` 的版本、安装方式、benchmark 是否一致。
- 如果 parity 数据变化，同步更新中文 README 中的表格。
- 如果 Bioconda/Crates.io/PyPI 状态变化，同步更新中文安装说明和 FAQ。
- 如果新增命令，同步更新中文 usage、适用场景和不适用场景。
- release notes 中可以加一个简短中文段落，说明这版对中文用户最重要的变化。
