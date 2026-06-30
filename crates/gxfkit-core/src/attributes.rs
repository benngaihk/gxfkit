//! Parsing of the GFF3 9th column (`key=value;key=value`).
//!
//! Values are kept as borrowed slices of the source line where possible. We
//! preserve insertion order because downstream serialization (GTF) wants a
//! stable, reproducible attribute order for diffing against AGAT.

/// An ordered list of GFF3 attribute key/value pairs.
///
/// GFF3 allows multi-valued attributes (comma-separated). We keep the raw value
/// string as-is; callers that care about multiplicity (e.g. `Parent`) can split
/// on commas themselves.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Attributes {
    pub pairs: Vec<(String, String)>,
}

impl Attributes {
    /// Parse a GFF3 attribute column. Empty / "." columns yield no pairs.
    pub fn parse_gff3(col: &str) -> Self {
        let mut pairs = Vec::new();
        if col == "." || col.is_empty() {
            return Self { pairs };
        }
        for field in col.split(';') {
            let field = field.trim();
            if field.is_empty() {
                continue;
            }
            match field.split_once('=') {
                Some((k, v)) => pairs.push((k.trim().to_string(), v.to_string())),
                // Tolerate a bare token with no '=' rather than dropping it.
                None => pairs.push((field.to_string(), String::new())),
            }
        }
        Self { pairs }
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.pairs
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    /// First value of a potentially multi-valued attribute (split on comma).
    pub fn first(&self, key: &str) -> Option<&str> {
        self.get(key).map(|v| v.split(',').next().unwrap_or(v))
    }

    pub fn is_empty(&self) -> bool {
        self.pairs.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic() {
        let a = Attributes::parse_gff3("ID=gene1;Name=BRCA2;Parent=x,y");
        assert_eq!(a.get("ID"), Some("gene1"));
        assert_eq!(a.first("Parent"), Some("x"));
        assert_eq!(a.get("missing"), None);
    }

    #[test]
    fn handles_dot_and_empty() {
        assert!(Attributes::parse_gff3(".").is_empty());
        assert!(Attributes::parse_gff3("").is_empty());
    }
}
