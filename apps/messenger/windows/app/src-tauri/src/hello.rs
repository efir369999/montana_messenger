//! THE DEVICE'S OWN CHECK BEFORE THE WORDS SHOW (iOS SeedShowView: LAContext .deviceOwnerAuthentication, «Show secret
//! phrase»): on Windows, Windows Hello -- the PIN, the face or the finger the person set for this account -- asked over the
//! app's window (UserConsentVerifier through IUserConsentVerifierInterop). No Hello set: the words stay hidden, as iOS keeps
//! them hidden on a phone without a passcode.

#[derive(serde::Serialize, Debug, PartialEq)]
pub enum Verdict {
    Verified,
    Refused,
    /// no PIN, face or finger on this account: nothing to protect the words with
    NotSet,
}

/// THE TESTS NEVER ASK A PERSON (the owner's word 20.10.2026: no Windows Hello, finger or PIN in automatic or background
/// checks): a window the test tools start (`MONTANA_NO_HELLO`, set by tools\ui.ps1) is refused at once -- no prompt is
/// shown and no word leaves. It can only refuse: the words still open behind the real Hello alone.
fn withheld() -> bool {
    std::env::var_os("MONTANA_NO_HELLO").is_some()
}

#[cfg(windows)]
pub fn verify(hwnd: isize, reason: &str) -> Verdict {
    use windows::core::{factory, HSTRING};
    if withheld() {
        return Verdict::Refused;
    }
    use windows::Security::Credentials::UI::{UserConsentVerificationResult, UserConsentVerifier, UserConsentVerifierAvailability};
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::WinRT::IUserConsentVerifierInterop;

    let available = UserConsentVerifier::CheckAvailabilityAsync().and_then(|op| op.join());
    if available != Ok(UserConsentVerifierAvailability::Available) {
        return Verdict::NotSet;
    }
    let Ok(interop) = factory::<UserConsentVerifier, IUserConsentVerifierInterop>() else { return Verdict::NotSet };
    // SAFETY: the app's own top-level window; the reason a HSTRING the call copies
    let op = unsafe {
        interop.RequestVerificationForWindowAsync::<windows_future::IAsyncOperation<UserConsentVerificationResult>>(
            HWND(hwnd as *mut _), &HSTRING::from(reason))
    };
    match op.and_then(|op| op.join()) {
        Ok(UserConsentVerificationResult::Verified) => Verdict::Verified,
        _ => Verdict::Refused,
    }
}

#[cfg(not(windows))]
pub fn verify(_: isize, _: &str) -> Verdict {
    if withheld() {
        return Verdict::Refused;
    }
    Verdict::NotSet
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A window of the tests is refused before Windows Hello is even asked whether it is set: no prompt can show (the
    /// handle is no window at all -- were Hello asked, it would fail, not prompt).
    #[test]
    fn a_window_of_the_tests_is_refused_and_nobody_is_asked() {
        std::env::set_var("MONTANA_NO_HELLO", "1");
        assert_eq!(verify(0, "test"), Verdict::Refused);
    }
}
