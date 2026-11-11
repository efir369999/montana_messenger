use std::ffi::c_char;

// Rejects a boundary that turns absent diagnostics into success, or invents a last error while
// reading that absence; malformed output arguments must not replace a genuine refusal either.
#[test]
fn a_missing_diagnostic_is_not_success_and_reading_it_creates_no_error() {
    // This integration binary owns its process: no other test can populate SAID first.
    let mut out = [b'x' as c_char; 256];
    let mut len = usize::MAX;
    for _ in 0..2 {
        assert_eq!(
            mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
            -2,
            "nothing has been said, so there is no successful diagnostic read"
        );
        assert_eq!(len, 0);
        assert_eq!(
            out[0], 0,
            "a stale caller buffer must not look like a diagnostic"
        );
    }
    out[0] = b'x' as c_char;
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), 0, &mut len),
        -3
    );
    assert_eq!(out[0], b'x' as c_char, "a zero capacity permits no write");
    assert_eq!(len, 0);
    assert_eq!(
        mt_boundary::mtc_last_said(std::ptr::null_mut(), out.len(), &mut len),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), std::ptr::null_mut()),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
        -2
    );

    assert_eq!(
        mt_boundary::mtc_pulse_status(out.as_mut_ptr(), out.len(), &mut len),
        -2
    );
    let status: Vec<u8> = out[..len].iter().map(|byte| *byte as u8).collect();
    assert_eq!(status, b"no diagnostics");
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
        -2,
        "reading pulse status must not populate SAID"
    );

    // A real door called before its device stands supplies the error; no mock populates SAID.
    let mut present = -1;
    assert_eq!(mt_boundary::mtc_person_stands(&mut present), -1);
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
        0
    );
    let original = out[..len].to_vec();
    let text: Vec<u8> = original.iter().map(|byte| *byte as u8).collect();
    assert!(String::from_utf8(text)
        .expect("diagnostic text")
        .contains("no device stands"));
    assert_eq!(
        mt_boundary::mtc_pulse_status(out.as_mut_ptr(), out.len(), &mut len),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_pulse_status(out.as_mut_ptr(), 0, &mut len),
        -3
    );
    assert_eq!(
        mt_boundary::mtc_pulse_status(std::ptr::null_mut(), out.len(), &mut len),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_pulse_status(out.as_mut_ptr(), out.len(), std::ptr::null_mut()),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
        0
    );
    assert_eq!(
        &out[..len],
        original.as_slice(),
        "pulse status must not overwrite SAID"
    );
    let needed = len;
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), needed, &mut len),
        -3
    );
    assert_eq!(len, needed);
    assert_eq!(
        mt_boundary::mtc_last_said(std::ptr::null_mut(), out.len(), &mut len),
        -2
    );
    assert_eq!(
        mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len),
        0
    );
    assert_eq!(
        &out[..len],
        original.as_slice(),
        "a failed read must preserve the actual error"
    );
}
