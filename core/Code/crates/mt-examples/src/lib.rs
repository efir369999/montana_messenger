use std::fmt::Write as _;

pub fn hex_full(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(&mut s, "{b:02x}");
    }
    s
}

pub fn xxd_dump(bytes: &[u8]) -> String {
    let mut s = String::new();
    let rows = (bytes.len() + 15) / 16;
    for row in 0..rows {
        let offset = row * 16;
        let end = (offset + 16).min(bytes.len());
        let slice = &bytes[offset..end];
        let _ = write!(&mut s, "{offset:08x}  ");
        for i in 0..16 {
            if i < slice.len() {
                let _ = write!(&mut s, "{:02x} ", slice[i]);
            } else {
                s.push_str("   ");
            }
            if i == 7 {
                s.push(' ');
            }
        }
        s.push_str(" |");
        for b in slice {
            if (0x20..0x7f).contains(b) {
                s.push(*b as char);
            } else {
                s.push('.');
            }
        }
        s.push_str("|\n");
    }
    s
}

pub fn print_section(title: &str) {
    println!();
    println!("================================================================================");
    println!("== {title}");
    println!("================================================================================");
}

pub fn print_subsection(title: &str) {
    println!();
    println!("-- {title} --");
}

pub fn print_field(label: &str, value: &str) {
    println!("  {label:<24} {value}");
}

pub fn print_kv(label: &str, value: impl std::fmt::Display) {
    println!("  {label:<24} {value}");
}

pub fn print_note(text: &str) {
    println!("  [note] {text}");
}

pub fn print_warn(text: &str) {
    eprintln!("  [warn] {text}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_full_empty() {
        assert_eq!(hex_full(&[]), "");
    }

    #[test]
    fn hex_full_single_byte() {
        assert_eq!(hex_full(&[0xAB]), "ab");
    }

    #[test]
    fn hex_full_preserves_order() {
        assert_eq!(hex_full(&[0x01, 0x23, 0xAB, 0xCD]), "0123abcd");
    }

    #[test]
    fn xxd_dump_exact_16_bytes() {
        let bytes: [u8; 16] = [
            0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD,
            0xEE, 0xFF,
        ];
        let out = xxd_dump(&bytes);
        assert!(out.starts_with("00000000  "));
        assert!(out.contains("00 11 22 33 44 55 66 77  88 99 aa bb cc dd ee ff"));
        assert!(out.contains("|"));
    }

    #[test]
    fn xxd_dump_short_row_padded() {
        let out = xxd_dump(&[0xAA, 0xBB]);
        assert!(out.starts_with("00000000  aa bb "));
    }

    #[test]
    fn xxd_dump_ascii_column() {
        let out = xxd_dump(b"Hello");
        assert!(out.contains("|Hello|"));
    }
}
