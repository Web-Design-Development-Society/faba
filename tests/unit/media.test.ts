// Pictures (MEDIA-01): the type comes from the file's first bytes, and the size limit is 2 MB.
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
