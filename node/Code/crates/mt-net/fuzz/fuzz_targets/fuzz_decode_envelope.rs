#![no_main]

use libfuzzer_sys::fuzz_target;
use mt_net::{decode_envelope, encode_envelope};

fuzz_target!(|data: &[u8]| {
    if let Ok(decoded) = decode_envelope(data) {
        let mut roundtrip = Vec::new();
        if encode_envelope(&decoded, &mut roundtrip).is_ok() {
            assert_eq!(roundtrip, data, "envelope roundtrip mismatch");
        }
    }
});
