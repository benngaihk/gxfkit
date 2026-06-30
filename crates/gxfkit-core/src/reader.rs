//! A streaming GFF3 line reader.

use crate::attributes::Attributes;
use crate::model::{Record, Strand};
use std::io::BufRead;

#[derive(Debug)]
pub enum ParseError {
    Io(std::io::Error),
    /// A data line that did not have 9 tab-separated columns.
    BadColumnCount {
        line_no: usize,
        found: usize,
    },
    BadCoordinate {
        line_no: usize,
        field: &'static str,
    },
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::Io(e) => write!(f, "I/O error: {e}"),
            ParseError::BadColumnCount { line_no, found } => {
                write!(f, "line {line_no}: expected 9 columns, found {found}")
            }
            ParseError::BadCoordinate { line_no, field } => {
                write!(f, "line {line_no}: invalid {field} coordinate")
            }
        }
    }
}

impl std::error::Error for ParseError {}

impl From<std::io::Error> for ParseError {
    fn from(e: std::io::Error) -> Self {
        ParseError::Io(e)
    }
}

/// Iterator-style reader. Comment lines (`#...`) and blank lines are skipped;
/// the FASTA section that may follow `##FASTA` is ignored.
pub struct GffReader<R: BufRead> {
    inner: R,
    line_no: usize,
    buf: String,
    in_fasta: bool,
}

impl<R: BufRead> GffReader<R> {
    pub fn new(inner: R) -> Self {
        Self {
            inner,
            line_no: 0,
            buf: String::new(),
            in_fasta: false,
        }
    }

    /// Returns the next record, `None` at EOF, or a parse error.
    pub fn next_record(&mut self) -> Result<Option<Record>, ParseError> {
        loop {
            self.buf.clear();
            let n = self.inner.read_line(&mut self.buf)?;
            if n == 0 {
                return Ok(None);
            }
            self.line_no += 1;
            let line = self.buf.trim_end_matches(['\n', '\r']);

            if self.in_fasta {
                continue;
            }
            if line.is_empty() {
                continue;
            }
            if let Some(rest) = line.strip_prefix('#') {
                if rest.starts_with("#FASTA") || line == "##FASTA" {
                    self.in_fasta = true;
                }
                continue;
            }
            // A bare ">" header without an explicit ##FASTA also begins FASTA.
            if line.starts_with('>') {
                self.in_fasta = true;
                continue;
            }

            return Ok(Some(self.parse_line(line)?));
        }
    }

    fn parse_line(&self, line: &str) -> Result<Record, ParseError> {
        let mut cols = line.splitn(9, '\t');
        let seqid = cols.next().unwrap_or_default();
        let source = next_col(&mut cols)?;
        let feature_type = next_col(&mut cols)?;
        let start_s = next_col(&mut cols)?;
        let end_s = next_col(&mut cols)?;
        let score = next_col(&mut cols)?;
        let strand_s = next_col(&mut cols)?;
        let phase = next_col(&mut cols)?;
        let attrs = match cols.next() {
            Some(a) => a,
            None => {
                return Err(ParseError::BadColumnCount {
                    line_no: self.line_no,
                    found: 8,
                })
            }
        };

        let start = start_s
            .parse::<u64>()
            .map_err(|_| ParseError::BadCoordinate {
                line_no: self.line_no,
                field: "start",
            })?;
        let end = end_s
            .parse::<u64>()
            .map_err(|_| ParseError::BadCoordinate {
                line_no: self.line_no,
                field: "end",
            })?;

        Ok(Record {
            seqid: seqid.to_string(),
            source: source.to_string(),
            feature_type: feature_type.to_string(),
            start,
            end,
            score: score.to_string(),
            strand: Strand::parse(strand_s),
            phase: phase.to_string(),
            attributes: Attributes::parse_gff3(attrs),
        })
    }
}

fn next_col<'a, I: Iterator<Item = &'a str>>(it: &mut I) -> Result<&'a str, ParseError> {
    it.next().ok_or(ParseError::BadColumnCount {
        line_no: 0,
        found: 0,
    })
}

/// Read every record into a `Vec`. Convenient for the spike where files fit in
/// memory; streaming callers should use `next_record` directly.
pub fn read_all<R: BufRead>(reader: R) -> Result<Vec<Record>, ParseError> {
    let mut r = GffReader::new(reader);
    let mut out = Vec::new();
    while let Some(rec) = r.next_record()? {
        out.push(rec);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn reads_records_skips_comments_and_fasta() {
        let data = "\
##gff-version 3
chr1\tEnsembl\tgene\t1\t100\t.\t+\t.\tID=g1
chr1\tEnsembl\tmRNA\t1\t100\t.\t+\t.\tID=t1;Parent=g1

##FASTA
>chr1
ACGT
";
        let recs = read_all(Cursor::new(data)).unwrap();
        assert_eq!(recs.len(), 2);
        assert_eq!(recs[0].id(), Some("g1"));
        assert_eq!(recs[1].parent(), Some("g1"));
    }
}
