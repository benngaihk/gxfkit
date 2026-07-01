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
    buf: Vec<u8>,
    in_fasta: bool,
}

impl<R: BufRead> GffReader<R> {
    pub fn new(inner: R) -> Self {
        Self {
            inner,
            line_no: 0,
            buf: Vec::new(),
            in_fasta: false,
        }
    }

    /// Returns the next record, `None` at EOF, or a parse error.
    ///
    /// Lines are read as raw bytes and decoded with `from_utf8_lossy`, so a stray
    /// non-UTF-8 byte (Latin-1 description text, etc.) is tolerated rather than
    /// aborting the whole conversion.
    pub fn next_record(&mut self) -> Result<Option<Record>, ParseError> {
        loop {
            self.buf.clear();
            let n = self.inner.read_until(b'\n', &mut self.buf)?;
            if n == 0 {
                return Ok(None);
            }
            self.line_no += 1;
            let raw = String::from_utf8_lossy(&self.buf);
            let line = raw.trim_end_matches(['\n', '\r']);

            if self.in_fasta {
                continue;
            }
            if line.is_empty() {
                continue;
            }
            if line.starts_with('#') {
                // The FASTA directive may carry trailing whitespace.
                if line.trim_end() == "##FASTA" {
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
        // The 9th (attribute) column may itself contain tabs, so cap the split at
        // 9. Anything fewer than 9 columns is malformed.
        let cols: Vec<&str> = line.splitn(9, '\t').collect();
        if cols.len() < 9 {
            return Err(ParseError::BadColumnCount {
                line_no: self.line_no,
                found: cols.len(),
            });
        }

        let start = cols[3]
            .parse::<u64>()
            .map_err(|_| ParseError::BadCoordinate {
                line_no: self.line_no,
                field: "start",
            })?;
        let end = cols[4]
            .parse::<u64>()
            .map_err(|_| ParseError::BadCoordinate {
                line_no: self.line_no,
                field: "end",
            })?;

        Ok(Record {
            seqid: cols[0].to_string(),
            source: cols[1].to_string(),
            feature_type: cols[2].to_string(),
            start,
            end,
            score: cols[5].to_string(),
            strand: Strand::parse(cols[6]),
            phase: cols[7].to_string(),
            attributes: Attributes::parse_gff3(cols[8]),
        })
    }
}

/// Read every record into a `Vec`. Convenient when the whole annotation is
/// needed at once (gff2gtf resolves the full feature graph); streaming callers
/// should use `next_record` directly.
pub fn read_all<R: BufRead>(reader: R) -> Result<Vec<Record>, ParseError> {
    let mut r = GffReader::new(reader);
    let mut out = Vec::new();
    while let Some(rec) = r.next_record()? {
        out.push(rec);
    }
    Ok(out)
}

/// Read every parseable record, reporting and skipping malformed data records.
///
/// I/O errors are still fatal. This is intentionally opt-in so the default
/// conversion path remains strict for AGAT parity.
pub fn read_all_sanitize<R, F>(
    reader: R,
    mut on_skip: F,
) -> Result<(Vec<Record>, usize), ParseError>
where
    R: BufRead,
    F: FnMut(&ParseError),
{
    let mut r = GffReader::new(reader);
    let mut out = Vec::new();
    let mut skipped = 0;
    loop {
        match r.next_record() {
            Ok(Some(rec)) => out.push(rec),
            Ok(None) => return Ok((out, skipped)),
            Err(ParseError::Io(e)) => return Err(ParseError::Io(e)),
            Err(e) => {
                skipped += 1;
                on_skip(&e);
            }
        }
    }
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

    #[test]
    fn tolerates_non_utf8_bytes() {
        // 0xE9 is Latin-1 'é' — invalid UTF-8. Must not abort; lossy-decoded.
        let mut data: Vec<u8> = b"chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=g1;Note=caf".to_vec();
        data.push(0xE9);
        data.push(b'\n');
        let recs = read_all(Cursor::new(data)).unwrap();
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].id(), Some("g1"));
    }

    #[test]
    fn too_few_columns_reports_line_and_count() {
        let data = b"chr1\tsrc\tgene\t1\t100\n".to_vec();
        match read_all(Cursor::new(data)) {
            Err(ParseError::BadColumnCount { line_no, found }) => {
                assert_eq!(line_no, 1);
                assert_eq!(found, 5);
            }
            other => panic!("expected BadColumnCount, got {other:?}"),
        }
    }

    #[test]
    fn sanitize_skips_bad_records_and_continues() {
        let data = b"\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=g1
bad\ttoo\tfew
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=t1;Parent=g1
"
        .to_vec();
        let mut diagnostics = Vec::new();
        let (recs, skipped) =
            read_all_sanitize(Cursor::new(data), |e| diagnostics.push(e.to_string())).unwrap();
        assert_eq!(skipped, 1);
        assert_eq!(recs.len(), 2);
        assert!(diagnostics[0].contains("line 2: expected 9 columns"));
    }
}
