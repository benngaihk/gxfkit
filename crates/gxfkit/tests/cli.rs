//! End-to-end CLI tests: run the built binary on plain and gzipped input.

use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const BIN: &str = env!("CARGO_BIN_EXE_gxfkit");
static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

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
    run_subcommand_args("gff2gtf", args, input)
}

fn run_gxf2gxf_args(args: &[&str], input: &[u8]) -> Output {
    run_subcommand_args("gxf2gxf", args, input)
}

fn run_subcommand_args(command: &str, args: &[&str], input: &[u8]) -> Output {
    let mut child = Command::new(BIN)
        .arg(command)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn gxfkit");
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

fn run_args(args: &[&str]) -> Output {
    Command::new(BIN)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .expect("run gxfkit")
}

fn temp_path(name: &str) -> PathBuf {
    let n = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!("gxfkit-cli-test-{}-{n}-{name}", std::process::id()))
}

#[test]
fn top_level_help_and_version_are_stable() {
    let help = run_args(&["help"]);
    assert!(
        help.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&help.stderr)
    );
    let help_stdout = String::from_utf8(help.stdout).unwrap();
    assert!(help_stdout.contains("USAGE:"));
    assert!(help_stdout.contains("gff2gtf"));
    assert!(help_stdout.contains("gxf2gxf"));

    let gff2gtf_help = run_args(&["gff2gtf", "--help"]);
    assert!(
        gff2gtf_help.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&gff2gtf_help.stderr)
    );
    let gff2gtf_help_stdout = String::from_utf8(gff2gtf_help.stdout).unwrap();
    assert!(gff2gtf_help_stdout.contains("refuses to overwrite"));

    let gxf2gxf_help = run_args(&["gxf2gxf", "--help"]);
    assert!(
        gxf2gxf_help.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&gxf2gxf_help.stderr)
    );
    let gxf2gxf_help_stdout = String::from_utf8(gxf2gxf_help.stdout).unwrap();
    assert!(gxf2gxf_help_stdout.contains("standardize GFF3"));
    assert!(gxf2gxf_help_stdout.contains("refuses to overwrite"));

    let version = run_args(&["version"]);
    assert!(
        version.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&version.stderr)
    );
    let version_stdout = String::from_utf8(version.stdout).unwrap();
    assert!(version_stdout.starts_with("gxfkit "));
}

#[test]
fn invalid_cli_arguments_fail_with_diagnostics() {
    let unknown = run_args(&["nope"]);
    assert!(!unknown.status.success(), "unknown subcommand should fail");
    assert!(String::from_utf8_lossy(&unknown.stderr).contains("unknown subcommand"));

    let unexpected = run_gff2gtf_args(&["--definitely-not-a-flag"], b"");
    assert!(
        !unexpected.status.success(),
        "unexpected gff2gtf argument should fail"
    );
    assert!(String::from_utf8_lossy(&unexpected.stderr).contains("unexpected argument"));

    let missing_value = run_gff2gtf_args(&["-g"], b"");
    assert!(
        !missing_value.status.success(),
        "missing flag value should fail"
    );
    assert!(String::from_utf8_lossy(&missing_value.stderr).contains("requires a value"));
}

#[test]
fn gxf2gxf_standardizes_direct_cds_and_refuses_overwrite() {
    let input = b"\
##gff-version 3
chr1\tRefSeq\tgene\t1\t100\t.\t+\t.\tID=gene1;locus_tag=LT001
chr1\tRefSeq\tCDS\t10\t50\t.\t+\t0\tID=cds1;Parent=gene1;protein_id=p1;locus_tag=LT001
";
    let out = run_gxf2gxf_args(&[], input);
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    let stdout = String::from_utf8(out.stdout).unwrap();
    assert!(stdout.starts_with("##gff-version 3\n"));
    assert!(stdout.contains("\tAGAT\tmRNA\t10\t50\t"));
    assert!(stdout.contains("ID=gene1;Parent=agat-gene-1"));
    assert!(stdout.contains("\tAGAT\texon\t10\t50\t"));
    assert!(stdout.contains("ID=agat-exon-1;Parent=gene1"));
    assert!(stdout.contains("\tRefSeq\tCDS\t10\t50\t.\t+\t0\tID=cds1;Parent=gene1"));

    let out_path = temp_path("standardized.gff3");
    let out_arg = out_path.to_string_lossy().to_string();
    let created = run_gxf2gxf_args(&["-o", &out_arg], input);
    assert!(
        created.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&created.stderr)
    );
    assert!(created.stdout.is_empty());

    fs::write(&out_path, "sentinel\n").unwrap();
    let refused = run_gxf2gxf_args(&["-o", &out_arg], input);
    assert!(!refused.status.success(), "existing output should fail");
    assert!(String::from_utf8_lossy(&refused.stderr).contains("refusing to overwrite"));
    assert_eq!(fs::read_to_string(&out_path).unwrap(), "sentinel\n");

    let _ = fs::remove_file(out_path);
}

#[test]
fn output_file_is_created_but_not_overwritten() {
    let out_path = temp_path("output.gtf");
    let out_arg = out_path.to_string_lossy().to_string();

    let created = run_gff2gtf_args(&["-o", &out_arg], GFF);
    assert!(
        created.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&created.stderr)
    );
    let written = fs::read_to_string(&out_path).unwrap();
    assert!(written.contains("gene_id \"g1\";"));
    assert!(created.stdout.is_empty());

    fs::write(&out_path, "sentinel\n").unwrap();
    let refused = run_gff2gtf_args(&["-o", &out_arg], GFF);
    assert!(!refused.status.success(), "existing output should fail");
    assert!(String::from_utf8_lossy(&refused.stderr).contains("refusing to overwrite"));
    assert_eq!(fs::read_to_string(&out_path).unwrap(), "sentinel\n");

    let _ = fs::remove_file(out_path);
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
