//! The in-memory record model.

use crate::attributes::Attributes;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strand {
    Forward,
    Reverse,
    Unstranded, // '.'
    Unknown,    // '?'
}

impl Strand {
    pub fn parse(s: &str) -> Strand {
        match s {
            "+" => Strand::Forward,
            "-" => Strand::Reverse,
            "?" => Strand::Unknown,
            _ => Strand::Unstranded,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Strand::Forward => "+",
            Strand::Reverse => "-",
            Strand::Unstranded => ".",
            Strand::Unknown => "?",
        }
    }
}

/// A single GFF/GTF feature line.
///
/// `score` and `phase` are kept as raw strings rather than parsed numbers so we
/// never lose or reformat the original token (important for byte-parity).
#[derive(Debug, Clone)]
pub struct Record {
    pub seqid: String,
    pub source: String,
    pub feature_type: String,
    pub start: u64,
    pub end: u64,
    pub score: String,
    pub strand: Strand,
    pub phase: String,
    pub attributes: Attributes,
}

impl Record {
    pub fn id(&self) -> Option<&str> {
        self.attributes.get("ID")
    }

    /// First parent (GFF3 permits multiple, comma-separated).
    pub fn parent(&self) -> Option<&str> {
        self.attributes.first("Parent")
    }
}
