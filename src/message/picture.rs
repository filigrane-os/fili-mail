//! Pictures of a message for the window: a `data:image/...;base64,` URI becomes a file in the cache
//! (Qt rich text loads files reliably, and the big base64 text never reaches the interface).
//! Only real PNG, JPEG, GIF, WebP and BMP bytes are kept; the size comes from the header.
use base64::{Engine, engine::general_purpose::STANDARD};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

pub const MAX_PICTURE: usize = 8 * 1024 * 1024;

/// (extension, width, height) of a picture, None when the bytes are not a supported image.
pub fn describe(b: &[u8]) -> Option<(&'static str, u32, u32)> {
    let be32 = |i: usize| b.get(i..i + 4).map(|x| u32::from_be_bytes([x[0], x[1], x[2], x[3]]));
    let le16 = |i: usize| b.get(i..i + 2).map(|x| u32::from(u16::from_le_bytes([x[0], x[1]])));
    let le24 = |i: usize| b.get(i..i + 3).map(|x| u32::from(x[0]) | u32::from(x[1]) << 8 | u32::from(x[2]) << 16);
    if b.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some(("png", be32(16)?, be32(20)?));
    }
    if b.starts_with(b"GIF87a") || b.starts_with(b"GIF89a") {
        return Some(("gif", le16(6)?, le16(8)?));
    }
    if b.starts_with(b"BM") {
        let w = u32::from_le_bytes(b.get(18..22)?.try_into().ok()?);
        let h = i32::from_le_bytes(b.get(22..26)?.try_into().ok()?).unsigned_abs();
        return Some(("bmp", w, h));
    }
    if b.starts_with(b"RIFF") && b.get(8..12) == Some(b"WEBP") {
        return match b.get(12..16)? {
            b"VP8X" => Some(("webp", le24(24)? + 1, le24(27)? + 1)),
            b"VP8L" => {
                let v = u32::from_le_bytes(b.get(21..25)?.try_into().ok()?);
                Some(("webp", (v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1))
            }
            b"VP8 " => Some(("webp", le16(26)? & 0x3fff, le16(28)? & 0x3fff)),
            _ => None,
        };
    }
    if b.starts_with(b"\xff\xd8\xff") {
        let mut i = 2;
        while i + 9 < b.len() {
            if b[i] != 0xff {
                i += 1;
                continue;
            }
            let marker = b[i + 1];
            if marker == 0xff {
                i += 1;
                continue;
            }
            if matches!(marker, 0xc0..=0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf) {
                let h = u32::from(u16::from_be_bytes([b[i + 5], b[i + 6]]));
                let w = u32::from(u16::from_be_bytes([b[i + 7], b[i + 8]]));
                return Some(("jpg", w, h));
            }
            if matches!(marker, 0xd8 | 0x01 | 0xd0..=0xd7) {
                i += 2;
            } else {
                i += 2 + usize::from(u16::from_be_bytes([b[i + 2], b[i + 3]]));
            }
        }
        return None;
    }
    None
}

fn cache_dir() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    let dir = base.join("fili-mail").join("images");
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir)
}

/// Store the picture bytes in the cache: (file:// url, width, height).
pub fn store_bytes(bytes: &[u8]) -> Option<(String, u32, u32)> {
    if bytes.is_empty() || bytes.len() > MAX_PICTURE {
        return None;
    }
    let (ext, w, h) = describe(bytes)?;
    if w == 0 || h == 0 || w > 20000 || h > 20000 {
        return None;
    }
    let name = format!("{:x}", Sha256::digest(bytes));
    let path = cache_dir()?.join(format!("{}.{ext}", &name[..32]));
    if !path.exists() {
        std::fs::write(&path, bytes).ok()?;
    }
    Some((format!("file://{}", path.display()), w, h))
}

/// Same for a `data:image/...;base64,` URI.
pub fn store_data_uri(uri: &str) -> Option<(String, u32, u32)> {
    let (head, payload) = uri.split_once(',')?;
    if !head.to_ascii_lowercase().starts_with("data:image/") || !head.to_ascii_lowercase().ends_with(";base64") {
        return None;
    }
    store_bytes(&STANDARD.decode(payload.trim()).ok()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn png_gif_and_jpeg_sizes_come_from_the_header() {
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend_from_slice(&300u32.to_be_bytes());
        png.extend_from_slice(&200u32.to_be_bytes());
        assert_eq!(describe(&png), Some(("png", 300, 200)));
        let mut gif = b"GIF89a".to_vec();
        gif.extend_from_slice(&[44, 1, 10, 0]);
        assert_eq!(describe(&gif), Some(("gif", 300, 10)));
        let jpeg = [0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xc0, 0, 11, 8, 0, 50, 0, 60, 1, 0, 0];
        assert_eq!(describe(&jpeg), Some(("jpg", 60, 50)));
    }

    #[test]
    fn other_bytes_are_refused() {
        assert_eq!(describe(b"<svg onload=alert(1)>"), None);
        assert!(store_data_uri("data:image/svg+xml;base64,PHN2Zz4=").is_none());
        assert!(store_bytes(b"not an image").is_none());
    }
}
