// Pictures (MEDIA-01): the type comes from the file's first bytes, and the size limit is 2 MB.
import { describe, expect, it } from 'vitest';
import { MAX_BYTES, pictureProblem, sniffPicture } from '../../src/lib/media';

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
