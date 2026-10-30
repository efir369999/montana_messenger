//! A FILM MADE LIGHT BEFORE IT GOES (iOS MontanaVideo.compressResumable in MontanaMediaKit.swift, the road of every film of a letter;
//! the precedent 23.08: «305 MB came out of the compression, and a file like that can be neither sent nor received»): Windows' own
//! Media Foundation writes the film again before its pieces go up -- H.264 within the 960 × 540 box of the export preset iOS takes
//! (AVAssetExportPreset960x540), the sound as AAC. A film already within the target (an .mp4 or .m4v whose long side is at most
//! 848 · 1.05 and whose picture is at most 2.5 Mbit/s · 1.3) goes as it is; so does a film this machine cannot read, or whose sound
//! cannot be written again (iOS: the sound is never dropped in silence -- the original goes with it). A phone's standing film leaves
//! upright in its pixels with no turn left in its track (iOS's own writer, MontanaVideo.upright: «what leaves is upright pixels with
//! no turn left for any receiver to read»; Windows' reader turns the picture itself). A written film that comes out black against
//! a living source is thrown away and the source goes (iOS isBlackOutput). One film at a time (iOS VideoCompressGate).
//! Windows' AAC encoder writes 96 kbit/s at the least; iOS writes 64 (48 for one channel) -- any player reads both.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

/// The box of iOS's export preset: the long side and the short.
const BOX: (f64, f64) = (960.0, 540.0);
/// iOS's own target (MontanaVideo.maxSide and the bitrate it judges by): a film within it goes as it is.
const MAX_SIDE: f64 = 848.0;
const MAX_RATE: f64 = 2_500_000.0;
/// One film at a time: two encoders hold two decode streams at once (iOS VideoCompressGate).
static GATE: Mutex<()> = Mutex::new(());

/// What a film is, read from its file.
#[derive(Debug, Clone, PartialEq)]
pub struct Film {
    /// the picture as it is stored, before its turn
    pub w: u32,
    pub h: u32,
    /// the track's turn, degrees clockwise (0, 90, 180, 270)
    pub turn: u32,
    pub fps: f64,
    pub seconds: f64,
    /// bits a second of the whole file (iOS: the track's estimatedDataRate)
    pub rate: f64,
    /// the sound: samples a second and channels
    pub sound: Option<(u32, u32)>,
}

/// How the film is written again: the picture upright, as it stands.
#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub w: u32,
    pub h: u32,
    pub fps: u32,
    pub bitrate: u32,
    pub sound: Option<(u32, u32)>,
}

/// Whether a film goes as it is (iOS: «already within the target: the source goes as it is»).
pub fn within(f: &Film, ext: &str) -> bool {
    let side = f.w.max(f.h) as f64;
    side <= MAX_SIDE * 1.05 && f.rate > 0.0 && f.rate <= MAX_RATE * 1.3 && matches!(ext, "mp4" | "m4v")
}

/// THE PLAN (the preset's box, iOS's own bitrate road): the picture as it stands -- Windows' reader turns a phone's film upright
/// itself, so the pixels leave upright with no turn left for any receiver to read (iOS's own writer: MontanaVideo.upright) --
/// fits the box by its long and short sides, never grows, its sides even; at most 30 frames a second; the bitrate follows the
/// frame's density against 848 × 478 at 1.6 Mbit/s, a short film gets more (under 10 s · 1.4, under 20 s · 1.25, under 30 s
/// · 1.1), between 0.5 and 4 Mbit/s. None -- the sound cannot be written again (AAC takes 44.1 or 48 kHz): the film goes as it is.
pub fn plan(f: &Film) -> Option<Plan> {
    let (sw, sh) = if f.turn % 180 == 90 { (f.h, f.w) } else { (f.w, f.h) };
    let (long, short) = (sw.max(sh) as f64, sw.min(sh) as f64);
    if long < 2.0 || short < 2.0 {
        return None;
    }
    let k = (BOX.0 / long).min(BOX.1 / short).min(1.0);
    let even = |x: f64| ((x / 2.0).round() as u32 * 2).max(16);
    let (w, h) = (even(sw as f64 * k), even(sh as f64 * k));
    let fps = (f.fps.round() as u32).clamp(1, 30);
    let mut bitrate = 1_600_000.0 * (w as f64 * h as f64) / (848.0 * 478.0);
    if f.seconds > 0.0 {
        bitrate *= if f.seconds < 10.0 { 1.4 } else if f.seconds < 20.0 { 1.25 } else if f.seconds < 30.0 { 1.1 } else { 1.0 };
    }
    let sound = match f.sound {
        Some((rate, ch)) if rate == 44_100 || rate == 48_000 => Some((rate, ch.clamp(1, 2))),
        Some(_) => return None,
        None => None,
    };
    Some(Plan { w, h, fps, bitrate: bitrate.clamp(500_000.0, 4_000_000.0) as u32, sound })
}

/// The share of a film written, and the word on it (iOS: «In queue» while another film is written, «Compressing» once its own
/// writing began).
pub enum Step {
    Waiting,
    Began,
    Share(f64),
}

/// A FILM WRITTEN AGAIN (iOS compressResumable): Some(the new file) -- the letter takes it under its own name; None -- the source
/// goes as it is. `stop` set ends the writing at once (the person's cross on the bubble).
pub fn squeeze(src: &Path, ext: &str, step: &dyn Fn(Step), stop: &AtomicBool) -> Option<PathBuf> {
    step(Step::Waiting);
    let _one = GATE.lock().unwrap_or_else(|e| e.into_inner());
    if stop.load(Ordering::SeqCst) {
        return None;
    }
    step(Step::Began);
    let _mf = mf::Started::new()?;
    let film = mf::probe(src)?;
    if within(&film, ext) {
        crate::trace_line(&format!("video road=source {}x{} rate={}k", film.w, film.h, (film.rate / 1000.0) as u64));
        return None;
    }
    let p = plan(&film)?;
    let out = std::env::temp_dir().join(format!("montana-film-{}-{}.mp4", std::process::id(), crate::wire::now_ms()));
    let t0 = std::time::Instant::now();
    let written = mf::write(src, &out, &p, film.seconds, &|s| step(Step::Share(s)), stop);
    if let Err(e) = written {
        crate::trace_line(&format!("video write failed {e} -- the source goes"));
        let _ = std::fs::remove_file(&out);
        return None;
    }
    if mf::black(&out, src, film.seconds) {
        crate::trace_line("video written black against a living source -- the source goes");
        let _ = std::fs::remove_file(&out);
        return None;
    }
    let size = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
    crate::trace_line(&format!("video road=written {}x{}->{}x{} turn={} {}k ms={} bytes={size}",
        film.w, film.h, p.w, p.h, film.turn, p.bitrate / 1000, t0.elapsed().as_millis()));
    step(Step::Share(1.0));
    Some(out)
}

#[cfg(windows)]
pub mod mf {
    use super::{Film, Plan};
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};
    use windows::core::{Error, GUID, HSTRING};
    use windows::Win32::Foundation::E_ABORT;
    use windows::Win32::Media::MediaFoundation::*;
    use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
    use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
    use windows::Win32::System::Variant::VT_I8;

    const VIDEO: u32 = MF_SOURCE_READER_FIRST_VIDEO_STREAM.0 as u32;
    const AUDIO: u32 = MF_SOURCE_READER_FIRST_AUDIO_STREAM.0 as u32;
    const ALL: u32 = MF_SOURCE_READER_ALL_STREAMS.0 as u32;
    const SOURCE: u32 = MF_SOURCE_READER_MEDIASOURCE.0 as u32;

    /// Media Foundation on this thread while it lives.
    pub struct Started;
    impl Started {
        pub fn new() -> Option<Started> {
            // SAFETY: COM and Media Foundation on this thread; MFStartup counts its starts, MFShutdown in drop ends this one
            unsafe {
                let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
                MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET).ok()?;
            }
            Some(Started)
        }
    }
    impl Drop for Started {
        fn drop(&mut self) {
            // SAFETY: the start of `new`
            unsafe {
                let _ = MFShutdown();
            }
        }
    }

    fn pair(a: u32, b: u32) -> u64 {
        ((a as u64) << 32) | b as u64
    }
    fn split(t: &IMFMediaType, key: &GUID) -> Option<(u32, u32)> {
        // SAFETY: a value read from a media type this thread holds
        let v = unsafe { t.GetUINT64(key) }.ok()?;
        Some(((v >> 32) as u32, v as u32))
    }
    fn attributes(n: u32) -> windows::core::Result<IMFAttributes> {
        let mut a: Option<IMFAttributes> = None;
        // SAFETY: the out pointer is a local Option
        unsafe { MFCreateAttributes(&mut a, n)? };
        a.ok_or_else(|| Error::from(E_ABORT))
    }
    /// The reader of a file; `process` -- it scales and converts the picture to what is asked (advanced video processing).
    fn reader(path: &Path, process: bool) -> windows::core::Result<IMFSourceReader> {
        let a = attributes(2)?;
        // SAFETY: attributes set on a store this thread made, the reader made from a path string
        unsafe {
            if process {
                a.SetUINT32(&MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, 1)?;
            }
            MFCreateSourceReaderFromURL(&HSTRING::from(path.to_string_lossy().as_ref()), &a)
        }
    }
    fn picture(w: u32, h: u32, fps: u32, subtype: &GUID) -> windows::core::Result<IMFMediaType> {
        // SAFETY: a new media type, filled here
        unsafe {
            let t = MFCreateMediaType()?;
            t.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
            t.SetGUID(&MF_MT_SUBTYPE, subtype)?;
            t.SetUINT64(&MF_MT_FRAME_SIZE, pair(w, h))?;
            if fps > 0 {
                t.SetUINT64(&MF_MT_FRAME_RATE, pair(fps, 1))?;
            }
            t.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, pair(1, 1))?;
            t.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
            Ok(t)
        }
    }
    fn sound(rate: u32, ch: u32, subtype: &GUID) -> windows::core::Result<IMFMediaType> {
        // SAFETY: a new media type, filled here
        unsafe {
            let t = MFCreateMediaType()?;
            t.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio)?;
            t.SetGUID(&MF_MT_SUBTYPE, subtype)?;
            t.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16)?;
            t.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, rate)?;
            t.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, ch)?;
            if *subtype == MFAudioFormat_AAC {
                t.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 12_000)?; // 96 kbit/s, the least Windows' AAC encoder writes
            } else {
                t.SetUINT32(&MF_MT_AUDIO_BLOCK_ALIGNMENT, ch * 2)?;
                t.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * ch * 2)?;
            }
            Ok(t)
        }
    }

    /// What the film is: its stored picture, its turn, frames a second, length, bits a second, sound.
    pub fn probe(path: &Path) -> Option<Film> {
        let r = reader(path, false).ok()?;
        // SAFETY: values read from the reader and its media types on this thread
        unsafe {
            let v = r.GetNativeMediaType(VIDEO, 0).ok()?;
            let (w, h) = split(&v, &MF_MT_FRAME_SIZE)?;
            let turn = v.GetUINT32(&MF_MT_VIDEO_ROTATION).unwrap_or(0) % 360;
            let fps = split(&v, &MF_MT_FRAME_RATE).filter(|f| f.1 > 0 && f.0 > 0).map(|(n, d)| n as f64 / d as f64).unwrap_or(30.0);
            let d = r.GetPresentationAttribute(SOURCE, &MF_PD_DURATION).ok()?;
            let seconds = d.Anonymous.Anonymous.Anonymous.uhVal as f64 / 1e7;
            let size = std::fs::metadata(path).map(|m| m.len() as f64).unwrap_or(0.0);
            let rate = match v.GetUINT32(&MF_MT_AVG_BITRATE) {
                Ok(b) if b > 0 => b as f64,
                _ if seconds > 0.0 => size * 8.0 / seconds,
                _ => 0.0,
            };
            let sound = r.GetNativeMediaType(AUDIO, 0).ok().map(|a| {
                (a.GetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND).unwrap_or(0), a.GetUINT32(&MF_MT_AUDIO_NUM_CHANNELS).unwrap_or(0))
            });
            Some(Film { w, h, turn, fps, seconds, rate, sound })
        }
    }

    /// THE WRITING (iOS's writer and the preset alike): the reader hands the picture upright, scaled to the plan, as NV12 and the
    /// sound as PCM; the writer lays H.264 (High, a key frame every two seconds, no reordered frames, the plan's mean bitrate) and
    /// AAC into an MP4. The two tracks are read side by side, the one behind first.
    pub fn write(src: &Path, out: &Path, p: &Plan, seconds: f64, share: &dyn Fn(f64), stop: &AtomicBool) -> windows::core::Result<()> {
        let r = reader(src, true)?;
        // SAFETY: Media Foundation objects made and used on this thread; samples pass from the reader to the writer as they come
        unsafe {
            r.SetStreamSelection(ALL, false)?;
            r.SetStreamSelection(VIDEO, true)?;
            // at most 30 frames a second; a reader that will not change the rate keeps the source's, and the writer follows it
            if r.SetCurrentMediaType(VIDEO, None, &picture(p.w, p.h, p.fps, &MFVideoFormat_NV12)?).is_err() {
                r.SetCurrentMediaType(VIDEO, None, &picture(p.w, p.h, 0, &MFVideoFormat_NV12)?)?;
            }
            let given = r.GetCurrentMediaType(VIDEO)?;
            let fps = split(&given, &MF_MT_FRAME_RATE).filter(|f| f.1 > 0).map(|(n, d)| n.div_ceil(d)).unwrap_or(p.fps);
            if let Some((rate, ch)) = p.sound {
                r.SetStreamSelection(AUDIO, true)?;
                r.SetCurrentMediaType(AUDIO, None, &sound(rate, ch, &MFAudioFormat_PCM)?)?;
            }
            let wa = attributes(2)?;
            wa.SetUINT32(&MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, 1)?;
            wa.SetUINT32(&MF_SINK_WRITER_DISABLE_THROTTLING, 1)?;
            let w = MFCreateSinkWriterFromURL(&HSTRING::from(out.to_string_lossy().as_ref()), None, &wa)?;
            let vt = picture(p.w, p.h, 0, &MFVideoFormat_H264)?;
            vt.SetUINT64(&MF_MT_FRAME_RATE, given.GetUINT64(&MF_MT_FRAME_RATE).unwrap_or(pair(fps, 1)))?;
            vt.SetUINT32(&MF_MT_AVG_BITRATE, p.bitrate)?;
            vt.SetUINT32(&MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_High.0 as u32)?;
            let vs = w.AddStream(&vt)?;
            let enc = attributes(4)?;
            enc.SetUINT32(&CODECAPI_AVEncMPVGOPSize, fps * 2)?;
            enc.SetUINT32(&CODECAPI_AVEncMPVDefaultBPictureCount, 0)?;
            enc.SetUINT32(&CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_UnconstrainedVBR.0 as u32)?;
            enc.SetUINT32(&CODECAPI_AVEncCommonMeanBitRate, p.bitrate)?;
            w.SetInputMediaType(vs, &given, &enc)?;
            let aus = match p.sound {
                Some((rate, ch)) => {
                    let s = w.AddStream(&sound(rate, ch, &MFAudioFormat_AAC)?)?;
                    w.SetInputMediaType(s, &r.GetCurrentMediaType(AUDIO)?, None)?;
                    Some(s)
                }
                None => None,
            };
            w.BeginWriting()?;
            let total = (seconds * 1e7).max(1.0);
            let (mut v_done, mut a_done) = (false, aus.is_none());
            let (mut v_at, mut a_at) = (0i64, 0i64);
            let mut said = -1i64;
            while !(v_done && a_done) {
                if stop.load(Ordering::SeqCst) {
                    return Err(Error::from(E_ABORT));
                }
                let video = !v_done && (a_done || v_at <= a_at);
                let (from, to) = if video { (VIDEO, vs) } else { (AUDIO, aus.unwrap_or(vs)) };
                let (mut flags, mut at, mut sample) = (0u32, 0i64, None::<IMFSample>);
                r.ReadSample(from, 0, None, Some(&mut flags as *mut u32), Some(&mut at as *mut i64), Some(&mut sample as *mut _))?;
                if flags & MF_SOURCE_READERF_ERROR.0 as u32 != 0 {
                    return Err(Error::from(E_ABORT));
                }
                let came = sample.is_some();
                match sample {
                    Some(s) => w.WriteSample(to, &s)?,
                    None if flags & MF_SOURCE_READERF_STREAMTICK.0 as u32 != 0 => w.SendStreamTick(to, at)?,
                    None => {}
                }
                // only a sample moves its track's time (the end of a stream says 0)
                if came && video {
                    v_at = at;
                    let pct = ((at as f64 / total) * 100.0) as i64;
                    if pct > said {
                        said = pct;
                        share((at as f64 / total).clamp(0.0, 1.0));
                    }
                } else if came {
                    a_at = at;
                }
                if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                    if video { v_done = true } else { a_done = true }
                }
            }
            w.Finalize()
        }
    }

    /// The light of the frame at `at` seconds, 0..1 (the picture's Y over video range, read small), or None.
    pub fn light(path: &Path, at: f64) -> Option<f64> {
        look(path, at).ok().flatten()
    }
    /// The same, with Media Foundation's word on what failed (for a check).
    pub fn look(path: &Path, at: f64) -> windows::core::Result<Option<f64>> {
        let r = reader(path, true)?;
        // SAFETY: the reader on this thread; the frame's buffer read only while locked, within its length
        unsafe {
            r.SetStreamSelection(ALL, false)?;
            r.SetStreamSelection(VIDEO, true)?;
            // read small, as the writing reads: the picture's own shape and frame rate, 64 wide
            let native = r.GetNativeMediaType(VIDEO, 0)?;
            let (w, h) = split(&native, &MF_MT_FRAME_SIZE).filter(|s| s.0 > 0).unwrap_or((64, 64));
            let (w, h) = if native.GetUINT32(&MF_MT_VIDEO_ROTATION).unwrap_or(0) % 180 == 90 { (h, w) } else { (w, h) };   // as it stands
            let (sw, sh) = (64u32, ((64 * h / w.max(1)) / 2 * 2).max(2));
            let small = picture(sw, sh, 0, &MFVideoFormat_NV12)?;
            if let Ok(rate) = native.GetUINT64(&MF_MT_FRAME_RATE) {
                small.SetUINT64(&MF_MT_FRAME_RATE, rate)?;
            }
            r.SetCurrentMediaType(VIDEO, None, &small)?;
            let mut pos = PROPVARIANT::default();
            (*pos.Anonymous.Anonymous).vt = VT_I8;
            (*pos.Anonymous.Anonymous).Anonymous.hVal = (at.max(0.0) * 1e7) as i64;
            r.SetCurrentPosition(&GUID::zeroed(), &pos)?;
            for _ in 0..60 {
                let (mut flags, mut sample) = (0u32, None::<IMFSample>);
                r.ReadSample(VIDEO, 0, None, Some(&mut flags as *mut u32), None, Some(&mut sample as *mut _))?;
                if let Some(s) = sample {
                    let b = s.ConvertToContiguousBuffer()?;
                    let (mut p, mut len) = (std::ptr::null_mut::<u8>(), 0u32);
                    b.Lock(&mut p, None, Some(&mut len as *mut u32))?;
                    let n = ((sw * sh) as usize).min(len as usize);
                    let y = std::slice::from_raw_parts(p, n);
                    let mean = y.iter().map(|&v| v as f64).sum::<f64>() / n.max(1) as f64;
                    let _ = b.Unlock();
                    return Ok(Some(((mean - 16.0) / 219.0).clamp(0.0, 1.0)));
                }
                if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                    return Ok(None);
                }
            }
            Ok(None)
        }
    }

    /// iOS isBlackOutput: at a tenth, a half and nine tenths, the written frame is near black where the source's is not -- at every
    /// moment judged; a truly dark film stays (its source is dark there too).
    pub fn black(out: &Path, src: &Path, seconds: f64) -> bool {
        let d = if seconds > 0.0 { seconds } else { 1.0 };
        let mut judged = false;
        for k in [0.1, 0.5, 0.9] {
            let (Some(lo), Some(ls)) = (light(out, d * k), light(src, d * k)) else { continue };
            judged = true;
            if lo > 0.03 || ls <= 0.03 {
                return false;
            }
        }
        judged
    }
}

#[cfg(not(windows))]
pub mod mf {
    use super::{Film, Plan};
    use std::path::Path;
    use std::sync::atomic::AtomicBool;
    pub struct Started;
    impl Started {
        pub fn new() -> Option<Started> {
            None
        }
    }
    pub fn probe(_: &Path) -> Option<Film> {
        None
    }
    pub fn write(_: &Path, _: &Path, _: &Plan, _: f64, _: &dyn Fn(f64), _: &AtomicBool) -> Result<(), String> {
        Err("no Media Foundation".into())
    }
    pub fn black(_: &Path, _: &Path, _: f64) -> bool {
        false
    }
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use windows::core::HSTRING;
    use windows::Win32::Media::MediaFoundation::*;

    /// A film of the test's own: a moving picture of `w` × `h` at 30 frames a second for `seconds`, H.264 at `rate`, a tone as AAC,
    /// the track turned by `turn` -- what a phone hands.
    fn film(path: &Path, w: u32, h: u32, seconds: u32, rate: u32, turn: u32, grain: bool) {
        let pair = |a: u32, b: u32| ((a as u64) << 32) | b as u64;
        // SAFETY: Media Foundation on this test's thread; every buffer locked only while filled
        unsafe {
            let _mf = mf::Started::new().unwrap();
            let wr = MFCreateSinkWriterFromURL(&HSTRING::from(path.to_string_lossy().as_ref()), None, None).unwrap();
            let vt = MFCreateMediaType().unwrap();
            vt.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video).unwrap();
            vt.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_H264).unwrap();
            vt.SetUINT32(&MF_MT_AVG_BITRATE, rate).unwrap();
            vt.SetUINT64(&MF_MT_FRAME_SIZE, pair(w, h)).unwrap();
            vt.SetUINT64(&MF_MT_FRAME_RATE, pair(30, 1)).unwrap();
            vt.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, pair(1, 1)).unwrap();
            vt.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32).unwrap();
            if turn != 0 {
                vt.SetUINT32(&MF_MT_VIDEO_ROTATION, turn).unwrap();
            }
            let vs = wr.AddStream(&vt).unwrap();
            let vi = MFCreateMediaType().unwrap();
            vi.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video).unwrap();
            vi.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12).unwrap();
            vi.SetUINT64(&MF_MT_FRAME_SIZE, pair(w, h)).unwrap();
            vi.SetUINT64(&MF_MT_FRAME_RATE, pair(30, 1)).unwrap();
            vi.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, pair(1, 1)).unwrap();
            vi.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32).unwrap();
            wr.SetInputMediaType(vs, &vi, None).unwrap();
            let at = MFCreateMediaType().unwrap();
            at.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio).unwrap();
            at.SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_AAC).unwrap();
            at.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16).unwrap();
            at.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, 48_000).unwrap();
            at.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, 2).unwrap();
            at.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24_000).unwrap();
            let aus = wr.AddStream(&at).unwrap();
            let ai = MFCreateMediaType().unwrap();
            ai.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio).unwrap();
            ai.SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_PCM).unwrap();
            ai.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16).unwrap();
            ai.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, 48_000).unwrap();
            ai.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, 2).unwrap();
            ai.SetUINT32(&MF_MT_AUDIO_BLOCK_ALIGNMENT, 4).unwrap();
            ai.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 192_000).unwrap();
            wr.SetInputMediaType(aus, &ai, None).unwrap();
            wr.BeginWriting().unwrap();
            let frame = (w * h * 3 / 2) as usize;
            let mut seed = 0x9E37_79B9u32;
            for i in 0..seconds * 30 {
                let buf = MFCreateMemoryBuffer(frame as u32).unwrap();
                let mut p = std::ptr::null_mut();
                buf.Lock(&mut p, None, None).unwrap();
                let px = std::slice::from_raw_parts_mut(p, frame);
                // a moving gradient under a camera's grain: as dense as a phone's film, which a smooth picture is not
                for y in 0..h as usize {
                    for x in 0..w as usize {
                        seed ^= seed << 13;
                        seed ^= seed >> 17;
                        seed ^= seed << 5;
                        px[y * w as usize + x] = (40 + ((x + y + i as usize * 8) % 150) + if grain { (seed % 30) as usize } else { 0 }) as u8;
                    }
                }
                px[(w * h) as usize..].fill(128);
                buf.Unlock().unwrap();
                buf.SetCurrentLength(frame as u32).unwrap();
                let s = MFCreateSample().unwrap();
                s.AddBuffer(&buf).unwrap();
                s.SetSampleTime(i as i64 * 333_333).unwrap();
                s.SetSampleDuration(333_333).unwrap();
                wr.WriteSample(vs, &s).unwrap();
                if i % 3 == 0 {
                    // a tenth of a second of a tone, two channels
                    let pcm: Vec<i16> = (0..4800).flat_map(|k| {
                        let v = ((((i / 3) * 4800 + k) as f32 * 440.0 * std::f32::consts::TAU / 48_000.0).sin() * 8000.0) as i16;
                        [v, v]
                    }).collect();
                    let bytes = (pcm.len() * 2) as u32;
                    let ab = MFCreateMemoryBuffer(bytes).unwrap();
                    let mut q = std::ptr::null_mut();
                    ab.Lock(&mut q, None, None).unwrap();
                    std::ptr::copy_nonoverlapping(pcm.as_ptr() as *const u8, q, bytes as usize);
                    ab.Unlock().unwrap();
                    ab.SetCurrentLength(bytes).unwrap();
                    let a = MFCreateSample().unwrap();
                    a.AddBuffer(&ab).unwrap();
                    a.SetSampleTime((i / 3) as i64 * 1_000_000).unwrap();
                    a.SetSampleDuration(1_000_000).unwrap();
                    wr.WriteSample(aus, &a).unwrap();
                }
            }
            wr.Finalize().unwrap();
        }
    }

    #[test]
    fn the_plan_fits_the_presets_box_and_follows_ios_bitrate_road() {
        let f = |w, h, seconds, sound| Film { w, h, turn: 0, fps: 59.94, seconds, rate: 20e6, sound };
        let p = plan(&f(1920, 1080, 45.0, Some((48_000, 2)))).unwrap();
        assert_eq!((p.w, p.h, p.fps), (960, 540, 30));
        assert_eq!(p.bitrate, (1_600_000.0 * 960.0 * 540.0 / (848.0 * 478.0)) as u32, "a long film: the density alone");
        let tall = plan(&f(1080, 1920, 5.0, None)).unwrap();
        assert_eq!((tall.w, tall.h), (540, 960), "a standing film keeps standing in the box");
        let turned = plan(&Film { turn: 90, ..f(1920, 1080, 5.0, None) }).unwrap();
        assert_eq!((turned.w, turned.h), (540, 960), "a phone's film stored on its side and turned 90 is written standing");
        assert_eq!(tall.bitrate, (1_600_000.0 * 540.0 * 960.0 / (848.0 * 478.0) * 1.4) as u32, "a short film gets more");
        let small = plan(&f(640, 360, 12.0, Some((44_100, 6)))).unwrap();
        assert_eq!((small.w, small.h, small.sound), (640, 360, Some((44_100, 2))), "never grows; six channels written as two");
        assert_eq!(small.bitrate, 500_000.max((1_600_000.0 * 640.0 * 360.0 / (848.0 * 478.0) * 1.25) as u32));
        assert!(plan(&f(1920, 1080, 10.0, Some((22_050, 1)))).is_none(), "a sound AAC cannot take: the source goes");
        let light = Film { w: 848, h: 478, turn: 0, fps: 30.0, seconds: 9.0, rate: 2_000_000.0, sound: None };
        assert!(within(&light, "mp4") && within(&light, "m4v"));
        assert!(!within(&light, "mov"), "only an mp4 or m4v goes as it is");
        assert!(!within(&Film { rate: 3_300_000.0, ..light.clone() }, "mp4"), "too dense");
        assert!(!within(&Film { w: 1280, h: 720, ..light }, "mp4"), "too large");
    }

    #[test]
    fn a_phones_film_is_written_into_the_box_with_its_sound_and_its_turn_and_comes_out_lighter() {
        let dir = std::env::temp_dir().join(format!("montana-film-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let src = dir.join("phone.mp4");
        film(&src, 1280, 720, 3, 8_000_000, 90, true);
        let _mf = mf::Started::new().unwrap();
        let read = mf::probe(&src).expect("the film is read");
        assert_eq!((read.w, read.h, read.turn), (1280, 720, 90), "the stored picture and its turn");
        assert!((read.seconds - 3.0).abs() < 0.2, "three seconds: {}", read.seconds);
        assert_eq!(read.sound, Some((48_000, 2)));
        let shares = std::cell::RefCell::new(vec![]);
        let out = squeeze(&src, "mp4", &|s| if let Step::Share(x) = s { shares.borrow_mut().push(x) }, &AtomicBool::new(false))
            .expect("a dense 1280 × 720 film is written again");
        let got = mf::probe(&out).expect("the written film is read");
        assert_eq!((got.w, got.h), (540, 960), "standing, within the preset's box");
        assert_eq!(got.turn, 0, "upright in its pixels, no turn left in the track");
        assert_eq!(got.sound, Some((48_000, 2)), "the sound is there");
        assert!((got.seconds - 3.0).abs() < 0.3, "as long as the source: {}", got.seconds);
        let (a, b) = (std::fs::metadata(&src).unwrap().len(), std::fs::metadata(&out).unwrap().len());
        assert!(b < a / 2, "lighter: {a} -> {b}");
        // the picture fills its frame: as light as the source's (bars of black would halve it)
        let looked = (mf::look(&out, 1.5), mf::look(&src, 1.5));
        let (Ok(Some(lo)), Ok(Some(ls))) = looked else { panic!("frames not read: {looked:?}") };
        assert!(ls > 0.3 && (lo - ls).abs() < 0.08, "the written frame as light as the source's: {lo} against {ls}");
        assert!(!mf::black(&out, &src, read.seconds), "a living picture");
        let s = shares.borrow();
        assert!(s.len() > 3 && s.windows(2).all(|p| p[0] <= p[1]) && *s.last().unwrap() == 1.0, "the share grows to the whole");
        // the written film is within the target? it is 960 wide -- iOS writes it again too; a film of 848 at a light rate is not
        let stop = AtomicBool::new(true);
        assert!(squeeze(&src, "mp4", &|_| {}, &stop).is_none(), "the person's cross ends it: the source stays");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_light_film_goes_as_it_is() {
        let dir = std::env::temp_dir().join(format!("montana-film-light-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let src = dir.join("light.mp4");
        film(&src, 640, 360, 2, 900_000, 0, false);
        let _mf = mf::Started::new().unwrap();
        let f = mf::probe(&src).unwrap();
        assert!(within(&f, "mp4"), "the test's light film is within the target: {f:?}");
        let began = std::cell::Cell::new(false);
        let out = squeeze(&src, "mp4", &|s| if let Step::Began = s { began.set(true) }, &AtomicBool::new(false));
        assert!(out.is_none(), "640 × 360 under 2.5 Mbit/s in an mp4: the source goes");
        assert!(began.get());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
