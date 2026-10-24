//! THE VOICE LETTER (iOS: AAC in an .m4a, 48 kHz, its length «du» and sixty points of its wave «wv»): the window hands the
//! microphone's samples raw, Windows' own Media Foundation encodes them as AAC in an MPEG-4 file -- what an iPhone plays. (The
//! web view's own recorder writes Opus in WebM, which iOS does not play.) Windows' AAC encoder offers 96 to 192 kbit/s; the
//! letter takes 96, iOS writes 64 -- any player reads both.

/// Sixty points of the wave, 0..255 (iOS «wv»): the loudest sample of each sixtieth, against the loudest of all.
pub fn wave(pcm: &[i16]) -> Vec<u8> {
    if pcm.is_empty() {
        return vec![0; 60];
    }
    let per = pcm.len().div_ceil(60);
    let peaks: Vec<u32> = pcm.chunks(per).map(|c| c.iter().map(|s| (*s as i32).unsigned_abs()).max().unwrap_or(0)).collect();
    let top = peaks.iter().copied().max().unwrap_or(1).max(1);
    let mut out: Vec<u8> = peaks.iter().map(|p| ((*p as u64 * 255) / top as u64) as u8).collect();
    out.resize(60, 0);
    out
}

#[cfg(windows)]
pub fn encode_m4a(pcm: &[i16], rate: u32) -> Option<Vec<u8>> {
    use windows::core::HSTRING;
    use windows::Win32::Media::MediaFoundation::*;
    use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
    if pcm.is_empty() || !(rate == 44_100 || rate == 48_000) {
        return None;
    }
    let path = std::env::temp_dir().join(format!("montana-voice-{}-{}.m4a", std::process::id(), crate::wire::now_ms()));
    let made = (|| -> windows::core::Result<()> {
        // SAFETY: Media Foundation on this thread, started and shut down here; every buffer is locked only while copied into
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET)?;
            let writer = MFCreateSinkWriterFromURL(&HSTRING::from(path.to_string_lossy().as_ref()), None, None)?;
            let out = MFCreateMediaType()?;
            out.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio)?;
            out.SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_AAC)?;
            out.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16)?;
            out.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, rate)?;
            out.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, 1)?;
            out.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 12_000)?;
            let stream = writer.AddStream(&out)?;
            let inp = MFCreateMediaType()?;
            inp.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio)?;
            inp.SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_PCM)?;
            inp.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16)?;
            inp.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, rate)?;
            inp.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, 1)?;
            inp.SetUINT32(&MF_MT_AUDIO_BLOCK_ALIGNMENT, 2)?;
            inp.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * 2)?;
            writer.SetInputMediaType(stream, &inp, None)?;
            writer.BeginWriting()?;
            let per = (rate / 10) as usize; // a tenth of a second per sample
            for (i, c) in pcm.chunks(per).enumerate() {
                let bytes = (c.len() * 2) as u32;
                let buf = MFCreateMemoryBuffer(bytes)?;
                let mut p: *mut u8 = std::ptr::null_mut();
                buf.Lock(&mut p, None, None)?;
                std::ptr::copy_nonoverlapping(c.as_ptr() as *const u8, p, bytes as usize);
                buf.Unlock()?;
                buf.SetCurrentLength(bytes)?;
                let s = MFCreateSample()?;
                s.AddBuffer(&buf)?;
                s.SetSampleTime((i as i64) * 1_000_000)?;
                s.SetSampleDuration((c.len() as i64) * 10_000_000 / rate as i64)?;
                writer.WriteSample(stream, &s)?;
            }
            writer.Finalize()?;
            drop(writer);
            let _ = MFShutdown();
        }
        Ok(())
    })();
    let file = made.ok().and_then(|_| std::fs::read(&path).ok());
    let _ = std::fs::remove_file(&path);
    file.filter(|f| f.len() > 64)
}

#[cfg(not(windows))]
pub fn encode_m4a(_: &[i16], _: u32) -> Option<Vec<u8>> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_second_of_tone_becomes_an_mp4_with_aac_and_its_wave() {
        let pcm: Vec<i16> = (0..48_000).map(|i| ((i as f32 * 440.0 * 2.0 * std::f32::consts::PI / 48_000.0).sin() * 12_000.0) as i16).collect();
        let m4a = encode_m4a(&pcm, 48_000).expect("Media Foundation encoded nothing");
        assert_eq!(&m4a[4..8], b"ftyp", "an MPEG-4 file");
        assert!(m4a.windows(4).any(|w| w == b"mp4a"), "its track is AAC");
        assert!(m4a.len() < 48_000, "a second at 96 kbit/s is about 12 KB, not raw");
        let w = wave(&pcm);
        assert_eq!(w.len(), 60);
        assert!(w.iter().all(|&p| p > 200), "a steady tone fills every point");
    }
}
