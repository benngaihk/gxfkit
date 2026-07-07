# gxfkit

[English](README.md) | 简体中文

> `gxfkit` 是一个用 Rust 实现的高速 GFF3/GTF 工具集，覆盖部分
> [AGAT](https://github.com/NBISweden/AGAT) 兼容工作流：生产支持的
> `gff2gtf`，以及 `main` 上的 `gxf2gxf` 标准化 beta。

`gxfkit` 目前聚焦在基因组注释流程里非常常见的 GFF3/GTF 转换场景，尤其是
`agat_convert_sp_gff2gtf.pl` 的替代路径。它不是 AGAT 的完整重写，而是一个
**可逐步替换的高性能子集**。

AGAT 仍然是本项目的正确性基准。`gxfkit` 的每个输出差异都应该被修复，或者在
[docs/PARITY.md](docs/PARITY.md) 中记录清楚。

> **当前状态：alpha。** 生产支持路径是 `gff2gtf`；在核心语料（人类 chr1、
> 人类 chr21、酵母）上，经过顺序无关的标准化比较后与 AGAT 100% 一致。
> `main` 还包含 `gxf2gxf` 标准化 beta：fixture 级别对齐 AGAT 1.7.0，并有
> 大语料残差账本；它还不是完整 AGAT 替代品。

---

## 为什么值得关注

在很多注释、转录组、泛基因组或流程交付任务中，GFF3/GTF 转换并不是分析的核心，
但会反复出现在流程关键路径上。AGAT 很可靠，但在大文件上可能比较慢。`gxfkit`
的定位是：

- **更快：** Rust 实现，当前基准中比 AGAT 快几十倍。
- **更容易塞进流程：** CLI 参数尽量贴近 AGAT 的常用脚本。
- **更重视可验证：** benchmark 和 parity harness 都在仓库里，可以一键复现。
- **不夸大兼容性：** 支持范围、已知差异和路线图公开记录。
- **可以试用下一步：** `main` 上已有 `gxf2gxf` 标准化 beta，适合用真实 GFF3
  文件做兼容性验证。

---

## 基准结果

以下数据来自 `benchmark/run.sh`：AGAT 1.7.0 和 `gxfkit` 在同一个 Linux 容器中运行，
使用固定公开 Ensembl 注释文件。完整方法见 [benchmark/](benchmark/)。

| 文件 | AGAT | gxfkit | 加速比 | AGAT 内存 | gxfkit 内存 | parity |
|------|------|--------|--------|-----------|-------------|--------|
| `human_chr1` | 47.19 s | 1.19 s | **39.7x** | 5.50 GB | 2.13 GB | 100.00% |
| `human_chr21` | 6.94 s | 150 ms | **46.3x** | 967 MB | 300 MB | 100.00% |
| `yeast` | 5.70 s | 100 ms | **57.0x** | 778 MB | 229 MB | 100.00% |

这里的 `parity` 是把两个工具的输出都经过 `tests/parity/normalize.py` 后再比较：
它会消除行顺序、属性顺序和空白差异，但不会掩盖真实的值差异；AGAT 中缺失的行和
`gxfkit` 额外输出的行都会扣分。详见
[docs/PARITY.md](docs/PARITY.md)。

---

## 安装

### GitHub Releases

打 tag 后，GitHub Releases 会发布以下平台的预编译包：

- Linux x86_64，静态 musl
- Linux aarch64，静态 musl
- macOS x86_64
- macOS aarch64

从 [GitHub Releases](https://github.com/benngaihk/gxfkit/releases) 下载对应平台的
`.tar.gz`，解压后把 `gxfkit` 放到 `PATH` 即可。

```bash
tar -xzf gxfkit-vX.Y.Z-linux-x86_64-static.tar.gz
./gxfkit-vX.Y.Z-linux-x86_64-static/gxfkit version
```

已发布的 `v0.0.1` 包早于“拒绝覆盖输出文件”保护；当前源码和 `v0.0.1` 之后的公开
发布才应具备该行为。公开安装审计默认会验证 no-overwrite 和核心语料 parity。

### 从源码编译

```bash
cargo build --release
./target/release/gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

如果要试用 `main` 上尚未发布的 `gxf2gxf` 标准化 beta：

```bash
cargo install --git https://github.com/benngaihk/gxfkit gxfkit
```

### Bioconda

```bash
conda install -c conda-forge -c bioconda gxfkit
```

当前公开的 Bioconda 包是 `0.0.2`，并已通过干净安装、smoke 转换和拒绝覆盖验证；
判断所有公开渠道能否作为严格生产证据前，请以发布状态文档为准。

### Crates.io

当前公开的 Crates.io 包是 `0.0.2`：

```bash
cargo install gxfkit --version 0.0.2
```

Crates.io 已通过干净安装、smoke 转换和拒绝覆盖验证；严格公开审计已经把
GitHub Release、Bioconda 和 Crates.io 记录为 `0.0.2` 的生产安装渠道。

### 计划中的分发方式

项目正在准备更适合生信用户的更多安装入口：

- Python/PyO3 绑定：`pip install gxfkit`

这些入口在正式发布前不应写进生产文档作为已可用渠道。

### Windows 编译说明

如果 MSVC Rust 工具链直接 `cargo build` 报
`LNK1181: cannot open input file 'kernel32.lib'`，请用仓库里的辅助脚本：

```powershell
powershell -File scripts/with-msvc-env.ps1 cargo build --release
```

---

## 使用

```text
gxfkit gff2gtf [-g <input.gff[.gz]>] [-o <output.gtf>] [--sanitize]
  -g, --gff <FILE>      输入 GFF3 文件，可为普通文本或 gzip，默认 stdin
  -o, --output <FILE>   输出 GTF 文件；拒绝覆盖已有文件，默认 stdout
  --sanitize            跳过格式错误的数据行，并把诊断写到 stderr
```

gzip 会自动识别：

```bash
gxfkit gff2gtf -g annotation.gff3.gz -o annotation.gtf
zcat annotation.gff3.gz | gxfkit gff2gtf > annotation.gtf
```

和 AGAT 一样，`gxfkit` 不会覆盖已有的 `-o/--output` 文件；重复运行前请先删除或重命名
旧输出。这个说明对应当前源码和 `v0.0.1` 之后的发布；公开 `v0.0.1` 包仍会覆盖已有
输出文件。

默认模式会在遇到格式错误的数据行时停止转换，方便暴露 parity 问题。只有在你明确想
跳过列数错误或坐标非法的记录、并通过 stderr 审计被跳过行时，才使用 `--sanitize`。

从 AGAT 替换过来：

```bash
agat_convert_sp_gff2gtf.pl -g annotation.gff3 -o annotation.gtf
```

改成：

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

`-i` 和 `--input` 也可以作为输入参数别名，方便接入已有流程。

### `gxf2gxf` 标准化 beta

`gxf2gxf` 是 M3 标准化引擎入口，目前覆盖第一批 AGAT 验证切片：标准 GFF3 写回、
父节点坐标修复、RefSeq 风格直接子层级补全，以及 FlyBase TE、orphan/self-parent
等 fixture 场景。更大的语料差异记录在
[docs/GXF2GXF-PARITY.md](docs/GXF2GXF-PARITY.md)。

```text
gxfkit gxf2gxf [-g <input.gff[.gz]>] [-o <output.gff>] [--sanitize]
  -g, --gff, --gxf <FILE>  输入 GFF3 文件，可为普通文本或 gzip，默认 stdin
  -o, --output <FILE>      输出 GFF3 文件；拒绝覆盖已有文件，默认 stdout
  --sanitize               跳过格式错误的数据行，并把诊断写到 stderr
```

---

## 正确性如何保证

1. **AGAT 1.7.0 是基准。** 支持范围内的输出以 AGAT 为 correctness oracle。
2. **真实语料对比。** 仓库提供固定公开语料和 Docker benchmark。
3. **标准化后 diff。** 只忽略顺序和空白这类不影响语义的差异。
4. **差异账本。** 所有接受的差异记录在 [docs/PARITY.md](docs/PARITY.md)。

如果你发现 AGAT 和 `gxfkit` 的真实输出差异，请提交 “AGAT parity divergence”
issue，并尽量附上最小可复现片段。

---

## 适合哪些用户试用

适合：

- 已经在流程中使用 `agat_convert_sp_gff2gtf.pl`，想降低运行时间。
- 需要处理较大的 Ensembl 风格 GFF3/GTF 注释文件。
- 愿意在正式替换前先跑 parity 检查的流程工程师或生信分析人员。
- 想用真实 GFF3 文件帮助测试 `gxf2gxf` 标准化 beta 的 AGAT 用户。

暂不建议直接替换：

- 强依赖 AGAT 全量命令矩阵的流程。
- 主要处理复杂不完整层级、并要求 AGAT 全量标准化行为的流程。
- 不能接受 alpha 阶段工具的生产环境。

---

## 中文社区

中文用户可以从这些入口开始：

- [中文 FAQ](docs/FAQ.zh-CN.md)
- [中文贡献指南](CONTRIBUTING.zh-CN.md)
- [中文社区维护指南](docs/COMMUNITY.zh-CN.md)
- GitHub Issues：可以使用中文提交 bug、功能请求或 AGAT parity 差异。

欢迎反馈真实数据上的兼容性问题。对这个项目来说，高质量的最小复现用例比泛泛的
“支持某格式”请求更有价值。

## License

MIT。AGAT 是 GPL-3.0 项目，由 NBIS 独立开发；`gxfkit` 是 clean-room
reimplementation，只把 AGAT 当作黑盒正确性基准。
