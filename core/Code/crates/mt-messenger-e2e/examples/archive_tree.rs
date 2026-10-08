// Stage 1 demo: materialize the local hierarchy "Montana/Chats/<chat>/".
// cargo run -p mt-messenger-e2e --example archive_tree -- <base>
// block_seq is assigned by the core as an end-to-end per-identity counter (not per-chat) — otherwise nonce repeats.
use mt_messenger_e2e::archive::{history_key, media_key, ArchiveStore, DIR_IN, DIR_OUT};

fn main() {
    let base = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/tmp/Монтана".into());
    let st = ArchiveStore::open(&base).unwrap();
    let hk = history_key(&[0x55u8; 32]);
    let mk = media_key(&[0x55u8; 32]);
    let acct = [0x33u8; 32];
    let device_id = [0x01u8; 16]; // one writer for this demo device

    for (chat, conv, msgs) in [
        (
            "Алиса",
            [0x22u8; 32],
            vec![(DIR_OUT, "привет"), (DIR_IN, "привет, как ты")],
        ),
        (
            "Боб",
            [0x44u8; 32],
            vec![(DIR_OUT, "фото ниже"), (DIR_IN, "ок")],
        ),
    ] {
        for (i, (dir, text)) in msgs.iter().enumerate() {
            let seq = st
                .append_item(
                    chat,
                    &hk,
                    &acct,
                    &device_id,
                    &conv,
                    *dir,
                    1000 + i as u64,
                    text.as_bytes(),
                )
                .unwrap();
            println!("{chat}: item → end-to-end block_seq={seq}");
        }
        st.put_media(chat, "demo.jpg", &mk, &acct, b"demo-media-bytes")
            .unwrap();
    }
    println!("Tree created at: {base}");
}
