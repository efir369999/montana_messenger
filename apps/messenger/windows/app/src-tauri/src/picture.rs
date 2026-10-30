//! THE PICTURES WEBVIEW2 DOES NOT DRAW (iOS writes HEIC: a sticker with its transparency, MontanaSticker.encode; the wall's
//! light pictures, MontanaFeeds; a photo a person picks): opened by Windows' own imaging (WIC, through the HEIF extension
//! the system carries) and handed to the window as PNG, the transparency kept. Nothing changes on the wire: the bytes kept
//! and sent stay the sender's own.

/// A picture of the HEIF family: an «ftyp» box of a HEIF brand (AVIF the web view draws itself).
pub fn is_heif(b: &[u8]) -> bool {
    b.len() > 12 && &b[4..8] == b"ftyp" && matches!(&b[8..12], b"heic" | b"heix" | b"hevc" | b"hevx" | b"heim" | b"heis" | b"mif1" | b"msf1")
}

/// The bytes as the window can draw them: a HEIF picture as PNG, anything else as it is (and a HEIF one as it is when this
/// computer has no HEIF extension).
pub fn viewable(b: Vec<u8>) -> Vec<u8> {
    if is_heif(&b) { png_of(&b).unwrap_or(b) } else { b }
}

/// Any picture WIC opens, as a PNG of its first frame in 32-bit BGRA.
#[cfg(windows)]
pub fn png_of(bytes: &[u8]) -> Option<Vec<u8>> {
    use windows::Win32::Graphics::Imaging::*;
    use windows::Win32::System::Com::StructuredStorage::IPropertyBag2;
    use windows::Win32::System::Com::*;
    use windows::Win32::UI::Shell::SHCreateMemStream;
    // SAFETY: COM objects of WIC used on this thread only; every buffer handed in lives through the call
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED); // already in another mode on a thread of the window: COM is there
        let f: IWICImagingFactory = CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER).ok()?;
        let input = f.CreateStream().ok()?;
        input.InitializeFromMemory(bytes).ok()?;
        let frame = f.CreateDecoderFromStream(&input, std::ptr::null(), WICDecodeMetadataCacheOnDemand).ok()?.GetFrame(0).ok()?;
        let conv = f.CreateFormatConverter().ok()?;
        conv.Initialize(&frame, &GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, None::<&IWICPalette>, 0.0, WICBitmapPaletteTypeCustom).ok()?;
        let (mut w, mut h) = (0u32, 0u32);
        conv.GetSize(&mut w, &mut h).ok()?;
        let out = SHCreateMemStream(None)?;
        let enc = f.CreateEncoder(&GUID_ContainerFormatPng, std::ptr::null()).ok()?;
        enc.Initialize(&out, WICBitmapEncoderNoCache).ok()?;
        let mut fe = None;
        enc.CreateNewFrame(&mut fe, std::ptr::null_mut()).ok()?;
        let fe = fe?;
        fe.Initialize(None::<&IPropertyBag2>).ok()?;
        fe.SetSize(w, h).ok()?;
        let mut format = GUID_WICPixelFormat32bppBGRA;
        fe.SetPixelFormat(&mut format).ok()?;
        fe.WriteSource(&conv, std::ptr::null()).ok()?;
        fe.Commit().ok()?;
        enc.Commit().ok()?;
        let mut size = 0u64;
        out.Seek(0, STREAM_SEEK_END, Some(&mut size)).ok()?;
        out.Seek(0, STREAM_SEEK_SET, None).ok()?;
        let mut png = vec![0u8; size as usize];
        let mut read = 0u32;
        out.Read(png.as_mut_ptr() as _, size as u32, Some(&mut read)).ok().ok()?;
        png.truncate(read as usize);
        Some(png)
    }
}

#[cfg(not(windows))]
pub fn png_of(_: &[u8]) -> Option<Vec<u8>> {
    None
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;

    /// A picture of the given BGRA pixels in a container of WIC's (HEIF here), for the test.
    fn encoded(container: &windows::core::GUID, bgra: &[u8], w: u32, h: u32) -> Option<Vec<u8>> {
        use windows::Win32::Graphics::Imaging::*;
        use windows::Win32::System::Com::StructuredStorage::IPropertyBag2;
        use windows::Win32::System::Com::*;
        use windows::Win32::UI::Shell::SHCreateMemStream;
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let f: IWICImagingFactory = CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER).ok()?;
            let src = f.CreateBitmapFromMemory(w, h, &GUID_WICPixelFormat32bppBGRA, w * 4, bgra).ok()?;
            let out = SHCreateMemStream(None)?;
            let enc = f.CreateEncoder(container, std::ptr::null()).ok()?;
            enc.Initialize(&out, WICBitmapEncoderNoCache).ok()?;
            let mut fe = None;
            enc.CreateNewFrame(&mut fe, std::ptr::null_mut()).ok()?;
            let fe = fe?;
            fe.Initialize(None::<&IPropertyBag2>).ok()?;
            fe.SetSize(w, h).ok()?;
            let mut format = GUID_WICPixelFormat32bppBGRA;
            fe.SetPixelFormat(&mut format).ok()?;
            fe.WriteSource(&src, std::ptr::null()).ok()?;
            fe.Commit().ok()?;
            enc.Commit().ok()?;
            let mut size = 0u64;
            out.Seek(0, STREAM_SEEK_END, Some(&mut size)).ok()?;
            out.Seek(0, STREAM_SEEK_SET, None).ok()?;
            let mut b = vec![0u8; size as usize];
            let mut read = 0u32;
            out.Read(b.as_mut_ptr() as _, size as u32, Some(&mut read)).ok().ok()?;
            b.truncate(read as usize);
            Some(b)
        }
    }

    #[test]
    fn a_heic_picture_comes_to_the_window_as_png() {
        let (w, h) = (64u32, 48u32);
        let bgra: Vec<u8> = (0..w * h).flat_map(|i| [(i % 64 * 4) as u8, 120, 200, 255]).collect();
        let heic = encoded(&windows::Win32::Graphics::Imaging::GUID_ContainerFormatHeif, &bgra, w, h)
            .expect("this computer's WIC writes HEIF (the HEIF and HEVC extensions)");
        assert!(is_heif(&heic), "an ftyp box of a HEIF brand: {:?}", &heic[4..12]);
        let png = viewable(heic);
        assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"), "the window gets a PNG");
        // the size kept: IHDR's width and height
        assert_eq!((u32::from_be_bytes(png[16..20].try_into().unwrap()), u32::from_be_bytes(png[20..24].try_into().unwrap())), (w, h));
        let jpeg = b"\xFF\xD8\xFF\xE0 not heif".to_vec();
        assert_eq!(viewable(jpeg.clone()), jpeg, "a picture the window draws stays as it is");
    }
}
