//! AEAD-wrapped post-handshake stream for the Noise_PQ transport.
//!
//! Wire framing (per direction): each application message is encrypted with
//! ChaCha20-Poly1305 using the derived session key (`sk_i_to_r` for initiator
//! → responder, `sk_r_to_i` for responder → initiator) and a monotonic
//! 64-bit nonce counter scoped to the direction (big-endian, 12-byte
//! ChaCha20-Poly1305 nonce = 4 zero bytes ‖ u64_be(counter)). Each frame is
//! prefixed by its 16-bit big-endian length (covering ciphertext + 16-byte
//! Poly1305 tag).
//!
//! Maximum plaintext frame size is 65 519 bytes (65 535 wire bytes minus the
//! 16-byte tag); larger application messages are fragmented by the caller.

use chacha20poly1305::aead::{AeadInPlace, KeyInit};
use chacha20poly1305::ChaCha20Poly1305;
use futures::io::{AsyncRead, AsyncWrite};
use pin_project_lite::pin_project;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use zeroize::Zeroize;

/// Maximum plaintext bytes per frame (16-bit length cap minus AEAD tag).
pub const NOISE_PQ_MAX_FRAME_PLAINTEXT: usize = u16::MAX as usize - 16;
const TAG_LEN: usize = 16;

pin_project! {
    pub struct NoisePqStream<S> {
        #[pin]
        inner: S,
        tx_key: ChaCha20Poly1305,
        rx_key: ChaCha20Poly1305,
        tx_nonce: u64,
        rx_nonce: u64,
        tx_buf: Vec<u8>,
        tx_buf_pos: usize,
        tx_pending_take: usize,
        rx_len_buf: [u8; 2],
        rx_len_pos: usize,
        rx_cipher_buf: Vec<u8>,
        rx_cipher_expected: usize,
        rx_cipher_pos: usize,
        rx_plain: Vec<u8>,
        rx_plain_pos: usize,
    }
}

impl<S> NoisePqStream<S> {
    /// Construct a new AEAD-wrapped stream. `tx_key` is the local-send /
    /// peer-receive key; `rx_key` is the local-receive / peer-send key.
    pub fn new(inner: S, tx_key: [u8; 32], rx_key: [u8; 32]) -> Self {
        let tx_aead = ChaCha20Poly1305::new(&tx_key.into());
        let rx_aead = ChaCha20Poly1305::new(&rx_key.into());
        let mut tk = tx_key;
        let mut rk = rx_key;
        tk.zeroize();
        rk.zeroize();
        NoisePqStream {
            inner,
            tx_key: tx_aead,
            rx_key: rx_aead,
            tx_nonce: 0,
            rx_nonce: 0,
            tx_buf: Vec::new(),
            tx_buf_pos: 0,
            tx_pending_take: 0,
            rx_len_buf: [0u8; 2],
            rx_len_pos: 0,
            rx_cipher_buf: Vec::new(),
            rx_cipher_expected: 0,
            rx_cipher_pos: 0,
            rx_plain: Vec::new(),
            rx_plain_pos: 0,
        }
    }
}

fn nonce_from_counter(counter: u64) -> [u8; 12] {
    let mut out = [0u8; 12];
    out[4..].copy_from_slice(&counter.to_be_bytes());
    out
}

fn encrypt_frame(key: &ChaCha20Poly1305, counter: u64, plaintext: &[u8]) -> io::Result<Vec<u8>> {
    if plaintext.len() > NOISE_PQ_MAX_FRAME_PLAINTEXT {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "frame too large",
        ));
    }
    let nonce = nonce_from_counter(counter);
    let mut buf = plaintext.to_vec();
    key.encrypt_in_place((&nonce).into(), &[], &mut buf)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "aead encrypt failed"))?;
    let mut out = Vec::with_capacity(2 + buf.len());
    let total = buf.len() as u16;
    out.extend_from_slice(&total.to_be_bytes());
    out.extend_from_slice(&buf);
    Ok(out)
}

fn decrypt_frame(
    key: &ChaCha20Poly1305,
    counter: u64,
    ciphertext_with_tag: &[u8],
) -> io::Result<Vec<u8>> {
    if ciphertext_with_tag.len() < TAG_LEN {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame too short",
        ));
    }
    let nonce = nonce_from_counter(counter);
    let mut buf = ciphertext_with_tag.to_vec();
    key.decrypt_in_place((&nonce).into(), &[], &mut buf)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "aead decrypt failed"))?;
    Ok(buf)
}

impl<S: AsyncWrite + Unpin> AsyncWrite for NoisePqStream<S> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        plaintext: &[u8],
    ) -> Poll<io::Result<usize>> {
        if plaintext.is_empty() {
            return Poll::Ready(Ok(0));
        }
        // Если предыдущий зашифрованный кадр ещё не дослан — дослать ЕГО и
        // вернуть ровно столько байт plaintext, сколько он покрывал. Новый
        // кадр НЕ шифруется (иначе при повторном вызове после Pending данные
        // дублируются в потоке → рассинхрон Yamux). Это корень мигов связи.
        if self.tx_buf_pos < self.tx_buf.len() {
            while self.tx_buf_pos < self.tx_buf.len() {
                let this = self.as_mut().project();
                let n =
                    futures::ready!(this.inner.poll_write(cx, &this.tx_buf[*this.tx_buf_pos..]))?;
                if n == 0 {
                    return Poll::Ready(Err(io::ErrorKind::WriteZero.into()));
                }
                *this.tx_buf_pos += n;
            }
            let take = self.tx_pending_take;
            let me = self.as_mut().project();
            me.tx_buf.clear();
            *me.tx_buf_pos = 0;
            *me.tx_pending_take = 0;
            return Poll::Ready(Ok(take));
        }
        // Буфер пуст — шифруем РОВНО один новый кадр.
        let take = plaintext.len().min(NOISE_PQ_MAX_FRAME_PLAINTEXT);
        let counter = self.tx_nonce;
        let frame = encrypt_frame(&self.tx_key, counter, &plaintext[..take])?;
        self.tx_nonce = self
            .tx_nonce
            .checked_add(1)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "tx nonce overflow"))?;
        let mut me = self.as_mut().project();
        *me.tx_buf = frame;
        *me.tx_buf_pos = 0;
        *me.tx_pending_take = take;
        // Пробуем дослать сразу. Недослали (Pending) — кадр сохранён, при
        // следующем вызове доходит верхняя ветка (без повторного шифрования).
        while *me.tx_buf_pos < me.tx_buf.len() {
            let n = futures::ready!(me
                .inner
                .as_mut()
                .poll_write(cx, &me.tx_buf[*me.tx_buf_pos..]))?;
            if n == 0 {
                return Poll::Ready(Err(io::ErrorKind::WriteZero.into()));
            }
            *me.tx_buf_pos += n;
        }
        let me = self.as_mut().project();
        me.tx_buf.clear();
        *me.tx_buf_pos = 0;
        *me.tx_pending_take = 0;
        Poll::Ready(Ok(take))
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.project();
        this.inner.poll_flush(cx)
    }

    fn poll_close(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.project();
        this.inner.poll_close(cx)
    }
}

impl<S: AsyncRead + Unpin> AsyncRead for NoisePqStream<S> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut [u8],
    ) -> Poll<io::Result<usize>> {
        loop {
            // Serve any decrypted plaintext sitting in rx_plain first.
            if self.rx_plain_pos < self.rx_plain.len() {
                let me = self.as_mut().project();
                let available = &me.rx_plain[*me.rx_plain_pos..];
                let n = available.len().min(buf.len());
                buf[..n].copy_from_slice(&available[..n]);
                *me.rx_plain_pos += n;
                if *me.rx_plain_pos == me.rx_plain.len() {
                    me.rx_plain.clear();
                    *me.rx_plain_pos = 0;
                }
                return Poll::Ready(Ok(n));
            }
            // Need to read & decrypt next frame. Step 1: read 2-byte length.
            if self.rx_len_pos < 2 {
                let me = self.as_mut().project();
                let n =
                    futures::ready!(me.inner.poll_read(cx, &mut me.rx_len_buf[*me.rx_len_pos..]))?;
                if n == 0 {
                    return Poll::Ready(Ok(0));
                }
                *me.rx_len_pos += n;
                continue;
            }
            // Step 2: parse length, ensure capacity.
            if self.rx_cipher_expected == 0 {
                let len = u16::from_be_bytes(self.rx_len_buf) as usize;
                if len == 0 || len < TAG_LEN {
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "noise_pq frame length invalid",
                    )));
                }
                let me = self.as_mut().project();
                *me.rx_cipher_expected = len;
                *me.rx_cipher_pos = 0;
                me.rx_cipher_buf.resize(len, 0);
            }
            // Step 3: read ciphertext bytes.
            if self.rx_cipher_pos < self.rx_cipher_expected {
                let me = self.as_mut().project();
                let start = *me.rx_cipher_pos;
                let n = futures::ready!(me
                    .inner
                    .poll_read(cx, &mut me.rx_cipher_buf[start..*me.rx_cipher_expected]))?;
                if n == 0 {
                    return Poll::Ready(Err(io::ErrorKind::UnexpectedEof.into()));
                }
                *me.rx_cipher_pos += n;
                continue;
            }
            // Step 4: decrypt full frame.
            let counter = self.rx_nonce;
            let next_nonce = self
                .rx_nonce
                .checked_add(1)
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "rx nonce overflow"))?;
            let me = self.as_mut().project();
            let pt = decrypt_frame(
                me.rx_key,
                counter,
                &me.rx_cipher_buf[..*me.rx_cipher_expected],
            )?;
            *me.rx_nonce = next_nonce;
            *me.rx_plain = pt;
            *me.rx_plain_pos = 0;
            *me.rx_len_pos = 0;
            *me.rx_cipher_expected = 0;
            *me.rx_cipher_pos = 0;
            // Continue loop to drain rx_plain on next iteration.
        }
    }
}

#[cfg(test)]
mod partial_write_tests {
    use super::*;
    use futures::io::{AsyncReadExt, AsyncWriteExt};
    use std::collections::VecDeque;
    use std::pin::Pin;
    use std::task::{Context, Poll};

    // Нижний слой, отдающий ёмкость записи по одному байту за poll и иногда
    // Pending — имитация реального TCP, где частичные записи частые. Именно
    // на таком слое прежний poll_write дублировал кадры (рассинхрон Yamux).
    struct Jittery {
        buf: VecDeque<u8>,
        allow: usize,
    }
    impl AsyncWrite for Jittery {
        fn poll_write(
            mut self: Pin<&mut Self>,
            cx: &mut Context<'_>,
            data: &[u8],
        ) -> Poll<io::Result<usize>> {
            if self.allow == 0 {
                self.allow = 1;
                // EXT-TEST-01: wake before returning Pending so the executor
                // re-polls; otherwise futures::executor::block_on hangs forever
                // (no waker was ever registered).
                cx.waker().wake_by_ref();
                return Poll::Pending;
            }
            self.allow -= 1;
            let n = data.len().min(1);
            for &b in &data[..n] {
                self.buf.push_back(b);
            }
            Poll::Ready(Ok(n))
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
            Poll::Ready(Ok(()))
        }
        fn poll_close(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }
    impl AsyncRead for Jittery {
        fn poll_read(
            mut self: Pin<&mut Self>,
            _cx: &mut Context<'_>,
            out: &mut [u8],
        ) -> Poll<io::Result<usize>> {
            let n = out.len().min(self.buf.len());
            for slot in out.iter_mut().take(n) {
                *slot = self.buf.pop_front().unwrap();
            }
            Poll::Ready(Ok(n))
        }
    }

    #[test]
    fn jittery_write_no_frame_duplication() {
        // Пишем три сообщения через дёргающийся слой, читаем тем же ключом —
        // расшифрованный поток обязан совпадать с исходным байт-в-байт.
        futures::executor::block_on(async {
            let key_tx = [7u8; 32];
            let key_rx = [9u8; 32];
            let wire = Jittery {
                buf: VecDeque::new(),
                allow: 0,
            };
            // tx пишет ключом key_tx; читатель должен читать тем же (его rx = key_tx).
            let mut writer = NoisePqStream::new(wire, key_tx, key_rx);
            let msgs: [&[u8]; 3] = [b"alpha", &[0xABu8; 4000], b"omega-final"];
            for m in &msgs {
                writer.write_all(m).await.unwrap();
            }
            // Забираем накопленный провод и читаем встречным потоком.
            let wire_bytes: Vec<u8> = {
                let inner = writer.inner;
                inner.buf.into_iter().collect()
            };
            let reader_wire = Jittery {
                buf: wire_bytes.into_iter().collect(),
                allow: usize::MAX,
            };
            let mut reader = NoisePqStream::new(reader_wire, key_rx, key_tx);
            let mut got = Vec::new();
            let mut chunk = [0u8; 8192];
            loop {
                let n = reader.read(&mut chunk).await.unwrap();
                if n == 0 {
                    break;
                }
                got.extend_from_slice(&chunk[..n]);
            }
            let mut expected = Vec::new();
            for m in &msgs {
                expected.extend_from_slice(m);
            }
            assert_eq!(
                got, expected,
                "поток расшифрован неверно — дублирование/потеря кадров"
            );
        });
    }
}
