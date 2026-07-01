#![no_main]

use gxfkit_core::reader::read_all;
use libfuzzer_sys::fuzz_target;
use std::io::Cursor;

fuzz_target!(|data: &[u8]| {
    let _ = read_all(Cursor::new(data));
});
