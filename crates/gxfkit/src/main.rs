//! gxfkit command-line entry point.
//!
//! Argument parsing is hand-rolled for the spike to keep compile times and the
//! dependency tree minimal. Flags mirror the AGAT scripts they replace so that
//! swapping `agat_convert_sp_gff2gtf.pl` for `gxfkit gff2gtf` is near-zero cost.

use std::fs::File;
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "\
gxfkit — fast GTF/GFF operations (drop-in subset of AGAT)

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
    gxfkit gff2gtf [-g <input.gff>] [-o <output.gtf>]

OPTIONS:
    -g, --gff <FILE>      Input GFF3 file (default: stdin)
    -o, --output <FILE>   Output GTF file (default: stdout)
    -h, --help            Show this message

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
        Err(e) => {
            eprintln!("gxfkit: error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn cmd_gff2gtf(args: &[String]) -> io::Result<()> {
    let mut input: Option<String> = None;
    let mut output: Option<String> = None;

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
            other => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("unexpected argument '{other}' (see `gxfkit gff2gtf --help`)"),
                ));
            }
        }
    }

    // Read input fully (spike: files fit in memory).
    let mut src = String::new();
    match input {
        Some(path) => {
            BufReader::new(File::open(&path)?).read_to_string(&mut src)?;
        }
        None => {
            io::stdin().read_to_string(&mut src)?;
        }
    }

    let records = gxfkit_core::reader::read_all(io::Cursor::new(src.as_bytes()))
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;

    let mut out: Box<dyn Write> = match output {
        Some(path) => Box::new(BufWriter::new(File::create(&path)?)),
        None => Box::new(BufWriter::new(io::stdout().lock())),
    };
    gxfkit_core::convert::gff3_to_gtf(&records, &mut out)?;
    out.flush()?;
    Ok(())
}

fn next_value<'a, I: Iterator<Item = &'a String>>(it: &mut I, flag: &str) -> io::Result<String> {
    it.next().cloned().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("flag '{flag}' requires a value"),
        )
    })
}
