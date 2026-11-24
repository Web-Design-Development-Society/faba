// Pictures (MEDIA-01): the type comes from the file's first bytes, and the size limit is 2 MB. The
// width and height come from the file's header too (MEDIA-04).
import { describe, expect, it } from 'vitest';
import {
  BANNER_SHAPE,
  fitWithin,
  MAX_BYTES,
  MAX_SIDE,
  MEDIUM_MAX_BYTES,
  MEDIUM_WIDTH,
  mediumCrop,
  mediumKey,
  pictureProblem,
  pictureSize,
  SIDE_LIMIT,
  sniffPicture,
  thumbKey,
  wholeCopy,
  wholeKey,
} from '../../src/lib/media';

const bytes = (...values: number[]) => new Uint8Array(values);
const JPEG = bytes(0xff, 0xd8, 0xff, 0xe0, 0, 0x10);
const PNG = bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d);
const WEBP = bytes(0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50);

describe('sniffPicture', () => {
  it('recognises JPEG, PNG and WebP by their first bytes', () => {
    expect(sniffPicture(JPEG)).toBe('image/jpeg');
    expect(sniffPicture(PNG)).toBe('image/png');
    expect(sniffPicture(WEBP)).toBe('image/webp');
  });

  it('refuses other formats, even when the file is named like a picture', () => {
    expect(sniffPicture(bytes(0x47, 0x49, 0x46, 0x38, 0x39, 0x61))).toBeNull();
    expect(sniffPicture(new TextEncoder().encode('<script>alert(1)</script>'))).toBeNull();
  });

  it('refuses a RIFF file that is not WebP', () => {
    expect(
      sniffPicture(bytes(0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45))
    ).toBeNull();
  });

  it('refuses an empty file', () => {
    expect(sniffPicture(new Uint8Array())).toBeNull();
  });
});

describe('pictureProblem', () => {
  it('accepts a JPEG under 2 MB', () => {
    expect(pictureProblem(120_000, JPEG)).toBeNull();
  });

  it('says what is wrong with the file', () => {
    expect(pictureProblem(0, JPEG)).toBe('Choose a picture to upload.');
    expect(pictureProblem(MAX_BYTES + 1, JPEG)).toBe('Use a picture under 2 MB.');
    expect(pictureProblem(1000, bytes(1, 2, 3))).toBe('Use a JPEG, PNG or WebP picture.');
  });

  it('allows exactly 2 MB', () => {
    expect(pictureProblem(MAX_BYTES, JPEG)).toBeNull();
  });
});

describe('fitWithin', () => {
  it('shrinks a phone photo to 1600 px on its longest side, keeping its shape', () => {
    expect(MAX_SIDE).toBe(1600);
    expect(fitWithin(4032, 3024)).toEqual({ width: 1600, height: 1200 });
    expect(fitWithin(3024, 4032)).toEqual({ width: 1200, height: 1600 });
  });

  it('leaves a small picture as it is, never making it bigger', () => {
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 });
    expect(fitWithin(1600, 900)).toEqual({ width: 1600, height: 900 });
  });
});

describe("a banner's medium copy (UI-27)", () => {
  it("is the middle band of a wide photo at a banner's 3:1, 1080 px wide", () => {
    expect(MEDIUM_WIDTH).toBe(1080);
    expect(mediumCrop(1600, 1200, BANNER_SHAPE)).toEqual({
      crop: { sx: 0, sy: 333, sw: 1600, sh: 533 },
      size: { width: 1080, height: 360 },
    });
  });

  it('is the middle band of a tall phone photo too', () => {
    expect(mediumCrop(1200, 1600, BANNER_SHAPE)).toEqual({
      crop: { sx: 0, sy: 600, sw: 1200, sh: 400 },
      size: { width: 1080, height: 360 },
    });
  });

  it('cuts the sides of a picture wider than its shape, and never makes it bigger', () => {
    expect(mediumCrop(1200, 300, BANNER_SHAPE)).toEqual({
      crop: { sx: 150, sy: 0, sw: 900, sh: 300 },
      size: { width: 900, height: 300 },
    });
  });

  it('weighs at most 400 KB, and is kept beside the picture and its small copy', () => {
    expect(MEDIUM_MAX_BYTES).toBe(400 * 1024);
    expect(mediumKey('groups/abc')).toBe('groups/abc-medium');
    expect(mediumKey('groups/abc')).not.toBe(thumbKey('groups/abc'));
  });
});

describe("a cover's medium copy (MEDIA-03)", () => {
  it('is the whole of a tall phone photo, 1080 px tall', () => {
    expect(wholeCopy(1200, 1600)).toEqual({
      crop: { sx: 0, sy: 0, sw: 1200, sh: 1600 },
      size: { width: 810, height: 1080 },
    });
  });

  it('is the whole of a wide photo, 1080 px wide', () => {
    expect(wholeCopy(1600, 1200)).toEqual({
      crop: { sx: 0, sy: 0, sw: 1600, sh: 1200 },
      size: { width: 1080, height: 810 },
    });
  });

  it('never makes a small picture bigger', () => {
    expect(wholeCopy(800, 600).size).toEqual({ width: 800, height: 600 });
  });

  it("is kept under a name of its own, so a cover's older cut copy is never shown", () => {
    expect(wholeKey('activities/abc')).toBe('activities/abc-whole');
    expect(wholeKey('activities/abc')).not.toBe(mediumKey('activities/abc'));
    expect(wholeKey('activities/abc')).not.toBe(thumbKey('activities/abc'));
  });
});

// Headers made by hand, as the formats lay them out, up to just past the size.
const ascii = (text: string) => [...text].map((c) => c.charCodeAt(0));
const be16 = (n: number) => [n >> 8, n & 0xff];
const be32 = (n: number) => [n >>> 24, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
const le16 = (n: number) => be16(n).reverse();
const le24 = (n: number) => [n & 0xff, (n >> 8) & 0xff, n >> 16];
const le32 = (n: number) => be32(n).reverse();

/** A PNG's signature and IHDR chunk. */
const png = (width: number, height: number) =>
  bytes(...PNG.slice(0, 8), ...be32(13), ...ascii('IHDR'), ...be32(width), ...be32(height), 8, 2);

/** A JPEG's start, a JFIF segment, `segments`, then a frame header (SOF) and the picture's data. */
function jpeg(width: number, height: number, segments: number[][] = [], frame = 0xc0) {
  const jfif = [0xff, 0xe0, ...be16(16), ...ascii('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
  const components = [1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1];
  const sof = [0xff, frame, ...be16(17), 8, ...be16(height), ...be16(width), 3, ...components];
  return bytes(0xff, 0xd8, ...jfif, ...segments.flat(), ...sof, 0xff, 0xda);
}

/**
 * An Exif segment whose IFD0 has a camera make and then `orientation`, in `order`: II is
 * little-endian, as Android phones write it, and MM big-endian, as iPhones do.
 */
function exif(orientation: number, order: 'II' | 'MM') {
  const [u16, u32] = order === 'II' ? [le16, le32] : [be16, be32];
  const make = [...u16(0x010f), ...u16(2), ...u32(4), ...ascii('ABC'), 0];
  const turn = [...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0];
  const tiff = [...ascii(order), ...u16(42), ...u32(8), ...u16(2), ...make, ...turn, ...u32(0)];
  const body = [...ascii('Exif'), 0, 0, ...tiff];
  return [0xff, 0xe1, ...be16(body.length + 2), ...body];
}

/** A WebP with its first chunk, `chunk`. */
const webp = (chunk: string, body: number[]) =>
  bytes(
    ...ascii('RIFF'),
    ...le32(12 + body.length),
    ...ascii('WEBP'),
    ...ascii(chunk),
    ...le32(body.length),
    ...body
  );

describe("a picture's width and height (MEDIA-04)", () => {
  it('reads a PNG’s', () => {
    expect(pictureSize(png(300, 400), 'image/png')).toEqual({ width: 300, height: 400 });
    expect(pictureSize(png(1600, 900), 'image/png')).toEqual({ width: 1600, height: 900 });
  });

  it('reads a JPEG’s from its frame header, baseline or progressive', () => {
    expect(pictureSize(jpeg(300, 400), 'image/jpeg')).toEqual({ width: 300, height: 400 });
    expect(pictureSize(jpeg(1200, 1600, [], 0xc2), 'image/jpeg')).toEqual({
      width: 1200,
      height: 1600,
    });
  });

  it('skips the segments before the frame header, even those whose marker is in its range', () => {
    const table = [0xff, 0xc4, ...be16(5), 0, 1, 2];
    const comment = [0xff, 0xfe, ...be16(6), ...ascii('ABCD')];
    expect(pictureSize(jpeg(640, 480, [table, comment]), 'image/jpeg')).toEqual({
      width: 640,
      height: 480,
    });
  });

  it('turns a JPEG whose orientation puts it on its side, in either byte order', () => {
    // A phone held upright saves a wide picture and says to turn it a quarter turn.
    const wide = (orientation: number, order: 'II' | 'MM') =>
      pictureSize(jpeg(1600, 1200, [exif(orientation, order)]), 'image/jpeg');
    expect(wide(6, 'MM')).toEqual({ width: 1200, height: 1600 });
    expect(wide(6, 'II')).toEqual({ width: 1200, height: 1600 });
    expect(wide(8, 'II')).toEqual({ width: 1200, height: 1600 });
    expect(wide(5, 'MM')).toEqual({ width: 1200, height: 1600 });
    // Upright, or upside down, it stays the way it is.
    expect(wide(1, 'II')).toEqual({ width: 1600, height: 1200 });
    expect(wide(3, 'MM')).toEqual({ width: 1600, height: 1200 });
  });

  it('keeps a JPEG’s size when its Exif can’t be read', () => {
    const odd = [0xff, 0xe1, ...be16(10), ...ascii('Exif'), 0, 0, ...ascii('XX')];
    expect(pictureSize(jpeg(1600, 1200, [odd]), 'image/jpeg')).toEqual({
      width: 1600,
      height: 1200,
    });
    // Exif that ends after IFD0 says how many entries it has, before them.
    const cut = exif(6, 'II').slice(0, 20);
    cut.splice(2, 2, ...be16(cut.length - 2));
    expect(pictureSize(jpeg(1600, 1200, [cut]), 'image/jpeg')).toEqual({
      width: 1600,
      height: 1200,
    });
  });

  it('reads the three kinds of WebP', () => {
    // Lossy: the top two bits of each side are a scale, not part of it.
    const lossy = webp('VP8 ', [
      0x10,
      0x02,
      0,
      0x9d,
      0x01,
      0x2a,
      ...le16(1080 | 0x4000),
      ...le16(810),
    ]);
    expect(pictureSize(lossy, 'image/webp')).toEqual({ width: 1080, height: 810 });
    // Lossless: 14 bits each, less one.
    const lossless = webp('VP8L', [0x2f, ...le32((300 - 1) | ((400 - 1) << 14))]);
    expect(pictureSize(lossless, 'image/webp')).toEqual({ width: 300, height: 400 });
    // Extended: 24 bits each, less one.
    const extended = webp('VP8X', [0x10, 0, 0, 0, ...le24(4000 - 1), ...le24(3000 - 1)]);
    expect(pictureSize(extended, 'image/webp')).toEqual({ width: 4000, height: 3000 });
  });

  it('gives no size when it can’t be read', () => {
    // A header cut short.
    expect(pictureSize(png(300, 400).slice(0, 20), 'image/png')).toBeNull();
    expect(pictureSize(JPEG, 'image/jpeg')).toBeNull();
    expect(pictureSize(WEBP, 'image/webp')).toBeNull();
    // A JPEG whose picture data comes before its size, or with something that isn't a marker.
    expect(pictureSize(bytes(0xff, 0xd8, 0xff, 0xda, 0, 2), 'image/jpeg')).toBeNull();
    expect(pictureSize(bytes(0xff, 0xd8, 0x12, 0x34, 0, 2), 'image/jpeg')).toBeNull();
    // A PNG whose first chunk isn't IHDR, and a WebP of a kind that isn't one of the three.
    const notIhdr = png(300, 400);
    notIhdr.set(ascii('IDAT'), 12);
    expect(pictureSize(notIhdr, 'image/png')).toBeNull();
    expect(pictureSize(webp('ALPH', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), 'image/webp')).toBeNull();
    // A lossy WebP without its start code.
    expect(
      pictureSize(webp('VP8 ', [0, 0, 0, 0, 0, 0, ...le16(300), ...le16(400)]), 'image/webp')
    ).toBeNull();
  });

  it('gives no size for a side of nothing, or one longer than a JPEG’s can be', () => {
    expect(pictureSize(png(0, 400), 'image/png')).toBeNull();
    expect(pictureSize(png(SIDE_LIMIT, 1), 'image/png')).toEqual({ width: SIDE_LIMIT, height: 1 });
    expect(pictureSize(png(SIDE_LIMIT + 1, 400), 'image/png')).toBeNull();
    const huge = webp('VP8X', [0, 0, 0, 0, ...le24(70000 - 1), ...le24(400 - 1)]);
    expect(pictureSize(huge, 'image/webp')).toBeNull();
  });
});
