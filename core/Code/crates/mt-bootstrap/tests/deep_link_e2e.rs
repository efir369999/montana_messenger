//! Stage 5 e2e: deep-link montana:// — the whole bootstrap invitation and resolving identity
//! (mt-address) to the overlay address through the production crates (address_to_account_id, overlay_addr).

use mt_bindings::{account_id_to_address, address_to_account_id};
use mt_bootstrap::{parse_deep_link, DeepLink, QRBootstrap, QR_KIND_DIRECT_V6};
use mt_overlay::overlay_addr;

#[test]
fn bootstrap_deep_link_full_journey() {
    // The friend makes a link → the new phone parses it → extracts the live endpoint.
    let mut ep = vec![0u8; 16];
    ep[15] = 1;
    ep.extend_from_slice(&8444u16.to_be_bytes());
    let q = QRBootstrap {
        dk: [0x5A; 32],
        expires: 2_000_000,
        ep_kind: QR_KIND_DIRECT_V6,
        ep,
    };
    let link = q.to_deep_link();
    assert!(link.starts_with("montana://b/"));
    match parse_deep_link(&link).unwrap() {
        DeepLink::Bootstrap(parsed) => {
            assert_eq!(parsed, q);
            assert_eq!(
                parsed.current_endpoint(1_000_000).unwrap().to_string(),
                "[::1]:8444"
            );
        },
        _ => panic!("expected Bootstrap"),
    }
}

#[test]
fn mt_address_deep_link_resolves_identity_to_overlay() {
    // montana:// montana://<mt-address> → account_id → overlay_addr, all through the production crates, byte-exact.
    let account_id = [0x7Au8; 32];
    let address = account_id_to_address(&account_id); // "mt..." Bitcoin-like
    assert!(address.starts_with("mt"));
    let link = format!("montana://{address}");
    match parse_deep_link(&link).unwrap() {
        DeepLink::Address(a) => {
            assert_eq!(a, address);
            // identity is recovered from the address (checksum matches)
            let resolved = address_to_account_id(&a).expect("valid mt-address");
            assert_eq!(resolved, account_id, "identity = wallet address");
            // account_id → recipient overlay address (deterministic, Stage 1)
            let ov = overlay_addr(&resolved);
            assert_eq!(
                ov,
                overlay_addr(&account_id),
                "overlay address byte-exact from identity"
            );
        },
        _ => panic!("expected Address"),
    }
}
