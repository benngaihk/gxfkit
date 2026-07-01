# FAQ

[English](FAQ.md) | 简体中文

## `gxfkit` 是 AGAT 的完整替代品吗？

不是。当前 alpha 阶段主要支持 `gff2gtf`，对应 AGAT 的
`agat_convert_sp_gff2gtf.pl`。完整命令矩阵见 [ROADMAP.md](ROADMAP.md)。

## 正确性基准是哪一个 AGAT 版本？

AGAT `1.7.0`。仓库使用固定 biocontainer 作为 parity 基准，详见
[PARITY.md](PARITY.md)。

## 如何把已有流程里的 AGAT 命令替换成 `gxfkit`？

原 AGAT 命令：

```bash
agat_convert_sp_gff2gtf.pl -g annotation.gff3 -o annotation.gtf
```

替换为：

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

`-i` 和 `--input` 也可作为输入参数别名，方便适配已有 pipeline。

正式替换前建议对自己的代表性数据跑一次 AGAT vs `gxfkit` diff，尤其是非 Ensembl
来源的注释文件。

## gzip 输入支持吗？

支持。`gxfkit` 会根据 magic bytes 自动识别 gzip，所以文件和管道都可以：

```bash
gxfkit gff2gtf -g annotation.gff3.gz -o annotation.gtf
zcat annotation.gff3.gz | gxfkit gff2gtf > annotation.gtf
```

## 输入文件有坏行时会怎样？

默认模式是严格的：格式错误的数据行会让转换停止，这样 parity 问题不会被悄悄吞掉。
对于真实世界里比较脏的文件，可以用 `gxfkit gff2gtf --sanitize` 跳过列数错误或坐标
非法的记录；每一条被跳过的行都会在 stderr 中留下诊断，方便审计。

## 为什么输出行顺序和 AGAT 不完全一样？

AGAT 的部分 sibling 排序来自内部 locus clustering / isoform 逻辑。`gxfkit` 使用可
复现的确定性遍历顺序。项目的 parity harness 会忽略单纯的行顺序差异，因此顺序不同
不一定代表结果错误。详见 [PARITY.md](PARITY.md) 中的 DIV-2。

## 什么时候不应该直接替换 AGAT？

以下场景建议谨慎：

- 流程依赖 AGAT 的其他命令，而不是只用 `agat_convert_sp_gff2gtf.pl`。
- 输入主要是 NCBI RefSeq 风格，存在 gene 直接挂 CDS、缺少 mRNA/transcript 层级等情况。
- 你依赖 AGAT 的完整 standardization 行为。
- 生产环境不能接受 alpha 阶段工具。

## 国内用户如何安装？

当前最稳妥的方式是使用 GitHub Releases 的预编译包，或从源码编译。Bioconda 是计划中
的分发渠道；在 recipe 正式合并前，不应假设 `conda install -c bioconda gxfkit` 已可用。

如果 GitHub 下载不稳定，可以先在能访问 GitHub 的环境下载 release archive，然后放到
内网或 HPC 软件目录中统一分发。

## 我发现 AGAT 和 `gxfkit` 输出不同，怎么办？

请提交 “AGAT parity divergence” issue，并包含：

- AGAT 版本。
- `gxfkit` 版本。
- AGAT 命令、`gxfkit` 命令和 diff 命令。
- 最小复现输入，或者公开数据链接。
- 标准化后的 diff，如果已经跑过。

越小的复现片段越容易被修复。
