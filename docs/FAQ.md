# FAQ

[English](FAQ.md) | [简体中文](FAQ.zh-CN.md)

## Is `gxfkit` a full AGAT replacement?

Not yet. The current alpha focuses on `gff2gtf`, mirroring
`agat_convert_sp_gff2gtf.pl` for the core Ensembl-style corpus. See
`docs/ROADMAP.md` for the planned command matrix.

## What AGAT version is the reference?

AGAT `1.7.0`, via the pinned biocontainer listed in `docs/PARITY.md`.

## How do I swap it into a pipeline?

For AGAT:

```bash
agat_convert_sp_gff2gtf.pl -g annotation.gff3 -o annotation.gtf
```

Use:

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

`-i` and `--input` are also accepted as input aliases for pipeline convenience.
`-o`/`--output` refuses to overwrite an existing file in the current source tree
and public releases after `v0.0.1`, matching AGAT's safer default; remove stale
outputs before rerunning a conversion. Public `v0.0.1` packages still overwrite
existing output files.

## Does gzip input work?

Yes. Gzip is detected from magic bytes, so both file and pipe forms work:

```bash
gxfkit gff2gtf -g annotation.gff3.gz -o annotation.gtf
zcat annotation.gff3.gz | gxfkit gff2gtf > annotation.gtf
```

## How does malformed input behave?

The default mode is strict: malformed data records stop the conversion so parity
failures are visible. For messy real-world files, `gxfkit gff2gtf --sanitize`
skips records with bad column counts or invalid coordinates and writes stderr
diagnostics for every skipped line.

## Why does my output order differ from AGAT?

Some AGAT sibling ordering is tied to internal locus clustering. `gxfkit` uses a
deterministic tree traversal. The parity harness normalizes order, so line order
alone is not considered a correctness failure. See DIV-2 in `docs/PARITY.md`.

## What if I find a real output difference?

Please open an "AGAT parity divergence" issue and include:

- the AGAT version
- the `gxfkit` version
- the exact commands
- a minimal input snippet
- the normalized diff, if available

If the difference is accepted rather than fixed, it should be documented in
`docs/PARITY.md`.
