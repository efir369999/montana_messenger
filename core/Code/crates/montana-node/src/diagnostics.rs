// Default diagnostics name an event without formatting identities, addresses or errors.
// The local operator must opt in before any detailed formatter is evaluated.

pub fn enabled(value: Option<&std::ffi::OsStr>) -> bool {
    value == Some(std::ffi::OsStr::new("1"))
}

pub fn message(enabled: bool, public: &'static str, detail: impl FnOnce() -> String) -> String {
    if enabled {
        detail()
    } else {
        public.to_owned()
    }
}

#[macro_export]
macro_rules! private_diagnostic {
    ($public:literal, $($detail:tt)*) => {{
        let setting = std::env::var_os("MONTANA_PRIVATE_DIAGNOSTICS");
        eprintln!("{}", $crate::diagnostics::message(
            $crate::diagnostics::enabled(setting.as_deref()),
            $public,
            || format!($($detail)*),
        ));
    }};
}

#[cfg(test)]
mod tests {
    use super::{enabled, message};
    use std::ffi::OsStr;

    #[test]
    fn default_never_evaluates_private_details() {
        // Rejects rendering a peer-bearing error before choosing the public message.
        assert_eq!(
            message(false, "connection failed", || panic!(
                "private formatter ran"
            )),
            "connection failed"
        );
    }

    #[test]
    fn only_exact_local_opt_in_enables_details() {
        // Rejects enabling disclosure merely because an environment variable exists.
        for value in [
            None,
            Some(""),
            Some("0"),
            Some("true"),
            Some(" 1"),
            Some("1 "),
        ] {
            assert!(!enabled(value.map(OsStr::new)));
        }
        assert!(enabled(Some(OsStr::new("1"))));
        assert_eq!(
            message(true, "connection failed", || "TEST_PEER_MARKER".into()),
            "TEST_PEER_MARKER"
        );
    }
}
