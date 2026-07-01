#![no_main]

use gxfkit_core::convert::gff3_to_gtf;
use gxfkit_core::reader::read_all;
use libfuzzer_sys::fuzz_target;
use std::io::Cursor;

fuzz_target!(|data: &[u8]| {
    if let Ok(records) = read_all(Cursor::new(data)) {
        let mut out = Vec::new();
        let _ = gff3_to_gtf(&records, &mut out);
    }
});
