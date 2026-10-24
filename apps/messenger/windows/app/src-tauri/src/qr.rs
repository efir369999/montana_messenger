//! The QR of the person's link (iOS MontanaCodeView: MontanaQR.image, CoreImage's CIQRCodeGenerator at correction level «L»,
//! the card passing no logo). Here: qrcodegen (Project Nayuki, MIT) at the same level, the modules handed to the window as one
//! SVG path, drawn module-sharp at any DPI as iOS draws them at whole device pixels.

use qrcodegen::{QrCode, QrCodeEcc};
use serde::Serialize;

#[derive(Serialize)]
pub struct Card {
    pub link: String,
    pub kind: String,
    /// modules per side, without the quiet zone
    pub size: i32,
    /// every dark module as a unit square, in module coordinates
    pub path: String,
    /// a temporary link renews at this moment (ms; iOS «The link renews on %@»), 0 for a permanent one
    pub renews: i64,
}

impl Card {
    pub fn of(link: String, kind: &str, renews: i64) -> Option<Card> {
        let q = QrCode::encode_text(&link, QrCodeEcc::Low).ok()?;
        let n = q.size();
        let mut path = String::new();
        for y in 0..n {
            let mut x = 0;
            while x < n {
                if q.get_module(x, y) {
                    let start = x;
                    while x < n && q.get_module(x, y) {
                        x += 1;
                    }
                    path.push_str(&format!("M{start} {y}h{}v1h-{}z", x - start, x - start));
                } else {
                    x += 1;
                }
            }
        }
        Some(Card { link, kind: kind.to_string(), size: n, path, renews })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_link_becomes_a_square_with_its_three_finders() {
        let c = Card::of(format!("https://montana.quest/perp/{}", "A".repeat(43)), "permanent", 0).unwrap();
        assert!(c.size >= 21 && (c.size - 17) % 4 == 0, "a QR side is 17 + 4·version modules");
        // the top-left finder's outer row is one run of seven modules
        assert!(c.path.starts_with("M0 0h7v1h-7z"));
    }
}
