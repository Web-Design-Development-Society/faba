// Pictures for activities and groups (MEDIA-01). A picture is a JPEG, PNG or WebP under 2 MB. The
// type comes from the file's own first bytes, not from the name or the type the browser sent, so
// a renamed file can't pass.

export const MAX_BYTES = 2 * 1024 * 1024;
export const ALT_MAX = 200;

/** The longest side a picture keeps when the device shrinks it before upload (src/scripts/pictures.ts). */
export const MAX_SIDE = 1600;

/** `width` by `height` scaled down to fit within `max` on its longest side. Never scaled up. */
export function fitWithin(width: number, height: number, max = MAX_SIDE) {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
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
