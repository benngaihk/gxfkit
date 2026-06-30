//! gxfkit-core: a fast, dependency-light core for reading GFF3/GTF and
//! converting between them.
//!
//! Design notes
//! ------------
//! For the M0 spike we deliberately hand-write a tight, allocation-conscious
//! line parser instead of pulling in `noodles`. GFF/GTF is column-oriented TSV
//! with a structured 9th column, so a custom parser is small, very fast, and —
//! crucially for AGAT byte-parity later — gives us total control over how the
//! output is re-serialized (quoting, attribute order, trailing separators).
//! We can swap to `noodles` behind this same API if it ever proves worthwhile.

pub mod attributes;
pub mod convert;
pub mod model;
pub mod reader;

pub use model::{Record, Strand};
pub use reader::{GffReader, ParseError};
