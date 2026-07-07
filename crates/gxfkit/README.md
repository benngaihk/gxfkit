# gxfkit

Fast command-line GFF/GTF utilities, implemented in Rust as an AGAT-compatible
subset. The current alpha production path focuses on `gff2gtf` parity for the
verified core corpus. `main` also includes an experimental first `gxf2gxf`
standardization slice; it is not yet a full AGAT replacement.

The first supported command is:

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

Experimental standardization entry point:

```bash
gxfkit gxf2gxf -g annotation.gff3 -o standardized.gff3
```

`-o/--output` refuses to overwrite an existing file, matching AGAT's safer
default for pipeline reruns.

See the repository README for benchmark, parity, and roadmap details:
https://github.com/benngaihk/gxfkit
