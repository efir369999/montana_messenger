#![no_main]

use libfuzzer_sys::fuzz_target;
use mt_net::{decode_frame, encode_frame};

fuzz_target!(|data: &[u8]| {
    if let Ok(frame) = decode_frame(data) {
        let mut roundtrip = Vec::new();
        if encode_frame(&frame, &mut roundtrip).is_ok() {
            assert_eq!(roundtrip, data, "frame roundtrip mismatch");
        }
    }
});
