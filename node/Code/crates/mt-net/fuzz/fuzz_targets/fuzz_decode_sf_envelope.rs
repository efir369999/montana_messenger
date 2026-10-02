#![no_main]

use libfuzzer_sys::fuzz_target;
use mt_net::{decode_sf_envelope, encode_sf_envelope};

fuzz_target!(|data: &[u8]| {
    if let Ok(env) = decode_sf_envelope(data) {
        let mut roundtrip = Vec::new();
        if encode_sf_envelope(&env, &mut roundtrip).is_ok() {
            assert_eq!(roundtrip, data, "sf envelope roundtrip mismatch");
        }
    }
});
