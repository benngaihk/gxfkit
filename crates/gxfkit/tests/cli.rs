//! End-to-end CLI tests: run the built binary on plain and gzipped input.

use std::io::Write;
use std::process::{Command, Output, Stdio};

const BIN: &str = env!("CARGO_BIN_EXE_gxfkit");

const GFF: &[u8] = b"\
##gff-version 3
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tParent=transcript:t1;exon_id=e1
";

/// Feed `input` to `gxfkit gff2gtf` on stdin, return stdout.
fn run_gff2gtf(input: &[u8]) -> String {
    let out = run_gff2gtf_args(&[], input);
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}

fn run_gff2gtf_args(args: &[&str], input: &[u8]) -> Output {
    let mut child = Command::new(BIN)
        .args(["gff2gtf"])
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn gxfkit");
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn plain_stdin_produces_gtf() {
    let gtf = run_gff2gtf(GFF);
    assert!(gtf.contains("gene_id \"g1\";"));
    assert!(gtf.contains("transcript_id \"t1\";"));
    assert!(gtf.contains("ID \"e1\";")); // synthesized exon ID
}

#[test]
fn gzipped_input_is_autodetected() {
    let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    enc.write_all(GFF).unwrap();
    let gz = enc.finish().unwrap();

    let from_gz = run_gff2gtf(&gz);
    let from_plain = run_gff2gtf(GFF);
    assert_eq!(from_gz, from_plain, "gzipped and plain output must match");
}

#[test]
fn sanitize_skips_malformed_records_with_diagnostics() {
    let input = b"\
##gff-version 3
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
bad\ttoo\tfew
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
";

    let strict = run_gff2gtf_args(&[], input);
    assert!(
        !strict.status.success(),
        "strict mode should reject bad input"
    );
    assert!(String::from_utf8_lossy(&strict.stderr).contains("expected 9 columns"));

    let sanitized = run_gff2gtf_args(&["--sanitize"], input);
    assert!(
        sanitized.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&sanitized.stderr)
    );
    let stderr = String::from_utf8_lossy(&sanitized.stderr);
    assert!(stderr.contains("--sanitize skipped malformed record"));
    assert!(stderr.contains("line 3: expected 9 columns"));

    let stdout = String::from_utf8(sanitized.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 2);
    assert!(stdout.contains("gene_id \"g1\";"));
    assert!(stdout.contains("transcript_id \"t1\";"));
}
