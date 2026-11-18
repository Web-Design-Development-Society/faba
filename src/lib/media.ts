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
 * The width of a cover's or banner's medium copy (UI-27), which a phone shows: the picture fills
 * the page's width, about 350 px on a screen two or three times as dense.
 */
export const MEDIUM_WIDTH = 1080;

/** The shape the page shows a picture at, width over height: a cover 16:9, a banner 3:1. */
export const SHAPES = { activity: 16 / 9, group: 3 } as const;

/** The most a medium copy weighs. At 1080 px wide, a JPEG is usually 100 to 300 KB. */
export const MEDIUM_MAX_BYTES = 400 * 1024;

/** Where a cover's or banner's medium copy is kept in the bucket, beside the picture. */
export function mediumKey(key: string): string {
  return `${key}-medium`;
}

/** `width` by `height` scaled down to fit within `max` on its longest side. Never scaled up. */
export function fitWithin(width: number, height: number, max = MAX_SIDE) {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

/**
 * A cover's or banner's medium copy: the middle of a `width` by `height` picture at `shape`, as
 * the page shows it, then at most 1080 px wide (UI-27). A tall phone photo keeps only the band the
 * page shows, so its copy is a fraction of the picture. Never scaled up.
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

/** Why a file can't be a picture, or null when it can. Only the file's size and first bytes count. */
export function pictureProblem(size: number, bytes: Uint8Array): string | null {
  if (size === 0) return 'Choose a picture to upload.';
  if (size > MAX_BYTES) return 'Use a picture under 2 MB.';
  if (sniffPicture(bytes) === null) return 'Use a JPEG, PNG or WebP picture.';
  return null;
}
