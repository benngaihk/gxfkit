//! gxfkit command-line entry point.
//!
//! Argument parsing is hand-rolled for the spike to keep compile times and the
//! dependency tree minimal. Flags mirror the AGAT scripts they replace so that
//! swapping `agat_convert_sp_gff2gtf.pl` for `gxfkit gff2gtf` is near-zero cost.

use std::fs::{File, OpenOptions};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "\
gxfkit — fast GTF/GFF operations (AGAT-compatible subset)

USAGE:
    gxfkit <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
    gff2gtf    Convert GFF3 to GTF
    help       Show this message
    version    Print version

Run `gxfkit <SUBCOMMAND> --help` for subcommand options.
";

const GFF2GTF_USAGE: &str = "\
gxfkit gff2gtf — convert GFF3 to GTF

USAGE:
    gxfkit gff2gtf [-g <input.gff>] [-o <output.gtf>] [--sanitize]

OPTIONS:
    -g, --gff <FILE>      Input GFF3 file, plain or gzipped (default: stdin)
    -o, --output <FILE>   Output GTF file; refuses to overwrite (default: stdout)
    --sanitize            Skip malformed data records with stderr diagnostics
    -h, --help            Show this message

Gzip input is auto-detected (magic bytes), from a file or stdin.
Aliases for AGAT compatibility: --gff, -i accepted for input.
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("gff2gtf") => run_result(cmd_gff2gtf(&args[1..])),
        Some("version") | Some("--version") | Some("-V") => {
            println!("gxfkit {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Some("help") | Some("--help") | Some("-h") | None => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Some(other) => {
            eprintln!("gxfkit: unknown subcommand '{other}'\n");
            print!("{USAGE}");
            ExitCode::FAILURE
        }
    }
}

fn run_result(r: io::Result<()>) -> ExitCode {
    match r {
        Ok(()) => ExitCode::SUCCESS,
        // A downstream `| head` closing the pipe is normal, not an error.
        Err(e) if is_broken_pipe(&e) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("gxfkit: error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn is_broken_pipe(e: &io::Error) -> bool {
    // ERROR_BROKEN_PIPE (109) / ERROR_NO_DATA (232) on Windows.
    e.kind() == io::ErrorKind::BrokenPipe || matches!(e.raw_os_error(), Some(109) | Some(232))
}

fn cmd_gff2gtf(args: &[String]) -> io::Result<()> {
    let mut input: Option<String> = None;
    let mut output: Option<String> = None;
    let mut sanitize = false;

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{GFF2GTF_USAGE}");
                return Ok(());
            }
            "-g" | "--gff" | "-i" | "--input" => {
                input = Some(next_value(&mut it, arg)?);
            }
            "-o" | "--output" => {
                output = Some(next_value(&mut it, arg)?);
            }
            "--sanitize" => {
                sanitize = true;
            }
            other => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("unexpected argument '{other}' (see `gxfkit gff2gtf --help`)"),
                ));
            }
        }
    }

    // Stream the input through the reader (gff2gtf needs the whole feature graph,
    // so records are still collected, but we don't slurp the file into a String
    // first — that would reject any non-UTF-8 byte). Gzip is auto-detected by
    // magic bytes, so plain or .gz input both work, from a file or stdin.
    let records = match input {
        Some(path) => {
            let reader = maybe_gunzip(File::open(&path)?)?;
            read_records(reader, sanitize)?
        }
        None => {
            let stdin = io::stdin();
            let reader = maybe_gunzip(stdin.lock())?;
            read_records(reader, sanitize)?
        }
    };

    let mut out: Box<dyn Write> = match output {
        Some(path) => Box::new(BufWriter::new(create_output(&path)?)),
        None => Box::new(BufWriter::new(io::stdout().lock())),
    };
    gxfkit_core::convert::gff3_to_gtf(&records, &mut out)?;
    out.flush()?;
    Ok(())
}

fn create_output(path: &str) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|e| {
            if e.kind() == io::ErrorKind::AlreadyExists {
                io::Error::new(
                    e.kind(),
                    format!("output file already exists, refusing to overwrite: {path}"),
                )
            } else {
                e
            }
        })
}

fn read_records<R: std::io::BufRead>(
    reader: R,
    sanitize: bool,
) -> io::Result<Vec<gxfkit_core::Record>> {
    if sanitize {
        let (records, skipped) = gxfkit_core::reader::read_all_sanitize(reader, |e| {
            eprintln!("gxfkit: warning: --sanitize skipped malformed record: {e}");
        })
        .map_err(parse_error_to_io)?;
        if skipped > 0 {
            eprintln!("gxfkit: warning: --sanitize skipped {skipped} malformed record(s)");
        }
        Ok(records)
    } else {
        gxfkit_core::reader::read_all(reader).map_err(parse_error_to_io)
    }
}

fn parse_error_to_io(e: gxfkit_core::reader::ParseError) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e.to_string())
}

/// Wrap `reader` in a gzip decoder if it begins with the gzip magic (`1f 8b`).
///
/// We read exactly the first two bytes (looping over short reads, which a pipe
/// may produce) and then chain them back in front of the rest, so detection is
/// independent of how the source chunks its data.
fn maybe_gunzip<R: Read + 'static>(mut reader: R) -> io::Result<Box<dyn std::io::BufRead>> {
    let mut magic = [0u8; 2];
    let mut n = 0;
    while n < magic.len() {
        match reader.read(&mut magic[n..])? {
            0 => break, // EOF before 2 bytes
            k => n += k,
        }
    }
    let head = magic[..n].to_vec();
    let combined = io::Cursor::new(head).chain(reader);
    if n == 2 && magic[0] == 0x1f && magic[1] == 0x8b {
        Ok(Box::new(BufReader::new(flate2::read::MultiGzDecoder::new(
            combined,
        ))))
    } else {
        Ok(Box::new(BufReader::new(combined)))
    }
}

fn next_value<'a, I: Iterator<Item = &'a String>>(it: &mut I, flag: &str) -> io::Result<String> {
    it.next().cloned().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("flag '{flag}' requires a value"),
        )
    })
}
