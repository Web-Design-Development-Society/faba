// Pictures for activities and groups (MEDIA-01). A picture is a JPEG, PNG or WebP under 2 MB. The
// type comes from the file's own first bytes, not from the name or the type the browser sent, so
// a renamed file can't pass.

export const MAX_BYTES = 2 * 1024 * 1024;
export const ALT_MAX = 200;

/** The longest side a picture keeps when the device shrinks it before upload (src/scripts/pictures.ts). */
export const MAX_SIDE = 1600;

/**
 * The longest side of a picture's small copy, which cards show: an activity's square (UI-03) and a
 * group's banner across its card (UI-10), which on a phone is about 340 px wide on a screen two or
 * three times as dense.
 */
export const THUMB_SIDE = 640;

/** The most a small copy weighs. At 640 px, a JPEG is usually 40 to 100 KB. */
export const THUMB_MAX_BYTES = 200 * 1024;

/** Where a picture's small copy is kept in the bucket, beside the picture. */
export function thumbKey(key: string): string {
  return `${key}-thumb`;
}

/**
 * The width of a banner's medium copy (UI-27), and the longest side of a cover's (MEDIA-03), which
 * a phone shows: the picture spans the page's width, about 350 px on a screen two or three times as
 * dense.
 */
export const MEDIUM_WIDTH = 1080;

/** A group's banner is a wide strip across its page, 3:1, width over height. */
export const BANNER_SHAPE = 3;

/** The most a medium copy weighs. At 1080 px wide, a JPEG is usually 100 to 300 KB. */
export const MEDIUM_MAX_BYTES = 400 * 1024;

/** Where a banner's medium copy is kept in the bucket, beside the picture. */
export function mediumKey(key: string): string {
  return `${key}-medium`;
}

/**
 * Where a cover's medium copy is kept, beside the picture. It's the whole picture (MEDIA-03), and
 * has a name of its own, so a cover added before then, whose medium copy is cut to 16:9, shows its
 * full picture, never the cut copy.
 */
export function wholeKey(key: string): string {
  return `${key}-whole`;
}

/** `width` by `height` scaled down to fit within `max` on its longest side. Never scaled up. */
export function fitWithin(width: number, height: number, max = MAX_SIDE) {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

/**
 * A banner's medium copy: the middle of a `width` by `height` picture at `shape`, as the page shows
 * it, then at most 1080 px wide (UI-27). A tall phone photo keeps only the band the page shows, so
 * its copy is a fraction of the picture. Never scaled up.
 */
export function mediumCrop(width: number, height: number, shape: number) {
  const [sw, sh] = width / height > shape ? [height * shape, height] : [width, width / shape];
  const out = Math.min(MEDIUM_WIDTH, Math.round(sw));
  return {
    crop: {
      sx: Math.round((width - sw) / 2),
      sy: Math.round((height - sh) / 2),
      sw: Math.round(sw),
      sh: Math.round(sh),
    },
    size: { width: out, height: Math.round(out / shape) },
  };
}

/**
 * A cover's medium copy: the whole `width` by `height` picture, since the page shows it whole
 * (MEDIA-03), at most 1080 px on its longest side. Never scaled up.
 */
export function wholeCopy(width: number, height: number) {
  return {
    crop: { sx: 0, sy: 0, sw: width, sh: height },
    size: fitWithin(width, height, MEDIUM_WIDTH),
  };
}

export type PictureType = 'image/jpeg' | 'image/png' | 'image/webp';

/** The picture's type from its first bytes, or null if it isn't a JPEG, PNG or WebP. */
export function sniffPicture(bytes: Uint8Array): PictureType | null {
  const starts = (sig: number[], offset = 0) =>
    bytes.length >= offset + sig.length && sig.every((b, i) => bytes[offset + i] === b);

  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  // RIFF, a four-byte size, then WEBP.
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  return null;
}

/** The longest side a picture's kept size can have, as for a JPEG. A bigger one's isn't kept. */
export const SIDE_LIMIT = 65535;

/** A picture's width and height in pixels, as it shows. */
export interface PictureSize {
  width: number;
  height: number;
}

/**
 * The width and height of the `type` picture in `bytes` as a browser shows it, read from its header
 * (MEDIA-04), or null if they can't be read. A JPEG turned on its side by its orientation tag, as a
 * phone's photo can be, is the other way round, since browsers turn it.
 */
export function pictureSize(bytes: Uint8Array, type: PictureType): PictureSize | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let size: PictureSize | null;
  try {
    size =
      type === 'image/jpeg'
        ? jpegSize(view)
        : type === 'image/png'
          ? pngSize(view)
          : webpSize(view);
  } catch {
    // A header cut short reads past the end.
    return null;
  }
  const fits = (side: number) => side >= 1 && side <= SIDE_LIMIT;
  return size && fits(size.width) && fits(size.height) ? size : null;
}

/** A PNG's size, from its first chunk, IHDR, after the 8-byte signature and the chunk's length. */
function pngSize(view: DataView): PictureSize | null {
  if (view.getUint32(12) !== 0x49484452) return null; // IHDR
  return { width: view.getUint32(16), height: view.getUint32(20) };
}

/** A WebP's size, from its first chunk: a lossy picture, a lossless one, or the extended header. */
function webpSize(view: DataView): PictureSize | null {
  const chunk = view.getUint32(12);
  if (chunk === 0x56503820) {
    // "VP8 ": after the frame's tag and start code, 14 bits each, little-endian.
    if (view.getUint8(23) !== 0x9d || view.getUint8(24) !== 0x01 || view.getUint8(25) !== 0x2a) {
      return null;
    }
    return { width: view.getUint16(26, true) & 0x3fff, height: view.getUint16(28, true) & 0x3fff };
  }
  if (chunk === 0x5650384c) {
    // "VP8L": after its signature, 14 bits each, less one.
    if (view.getUint8(20) !== 0x2f) return null;
    const bits = view.getUint32(21, true);
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
  }
  if (chunk === 0x56503858) {
    // "VP8X": after its flags, 24 bits each, little-endian, less one.
    const side = (at: number) => view.getUint16(at, true) + (view.getUint8(at + 2) << 16) + 1;
    return { width: side(24), height: side(27) };
  }
  return null;
}

/**
 * A JPEG's size, from its frame header (SOF), which comes before its picture data. An Exif segment
 * before it can say it's turned on its side.
 */
function jpegSize(view: DataView): PictureSize | null {
  let sideways = false;
  let at = 2;
  while (at + 1 < view.byteLength) {
    if (view.getUint8(at) !== 0xff) return null;
    const marker = view.getUint8(at + 1);
    if (marker === 0xff) {
      // Padding before a marker.
      at += 1;
      continue;
    }
    // Markers with nothing after them.
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      at += 2;
      continue;
    }
    // The picture's data, or its end, before its size.
    if (marker === 0xda || marker === 0xd9) return null;
    const length = view.getUint16(at + 2);
    if (marker === 0xe1 && !sideways) sideways = turnedOnSide(view, at + 4, length - 2);
    // Every frame header but DHT (C4), JPG (C8) and DAC (CC), which share their range.
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      const height = view.getUint16(at + 5);
      const width = view.getUint16(at + 7);
      return sideways ? { width: height, height: width } : { width, height };
    }
    at += 2 + length;
  }
  return null;
}

/**
 * Whether the APP1 segment at `start`, `length` bytes long, is Exif whose orientation is 5 to 8,
 * which turns the picture a quarter turn. Anything else, or Exif that can't be read, isn't.
 */
function turnedOnSide(view: DataView, start: number, length: number): boolean {
  try {
    // "Exif" and two zero bytes, then a TIFF header: its byte order and where IFD0 is.
    if (view.getUint32(start) !== 0x45786966 || view.getUint16(start + 4) !== 0) return false;
    const tiff = start + 6;
    const order = view.getUint16(tiff);
    if (order !== 0x4949 && order !== 0x4d4d) return false;
    const little = order === 0x4949;
    const ifd = tiff + view.getUint32(tiff + 4, little);
    const entries = view.getUint16(ifd, little);
    for (let i = 0; i < entries; i++) {
      const entry = ifd + 2 + i * 12;
      if (entry + 12 > start + length) return false;
      if (view.getUint16(entry, little) === 0x0112) {
        const orientation = view.getUint16(entry + 8, little);
        return orientation >= 5 && orientation <= 8;
      }
    }
    return false;
  } catch {
    return false;
  }
}

/** Why a file can't be a picture, or null when it can. Only the file's size and first bytes count. */
export function pictureProblem(size: number, bytes: Uint8Array): string | null {
  if (size === 0) return 'Choose a picture to upload.';
  if (size > MAX_BYTES) return 'Use a picture under 2 MB.';
  if (sniffPicture(bytes) === null) return 'Use a JPEG, PNG or WebP picture.';
  return null;
}
