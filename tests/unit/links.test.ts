import { describe, expect, it } from 'vitest';
import { linkify, mapsUrl } from '../../src/lib/links';

describe('linkify', () => {
  it('leaves text without addresses as it is', () => {
    expect(linkify('Bring water.\nWe go slowly.')).toEqual([
      { text: 'Bring water.\nWe go slowly.' },
    ]);
    expect(linkify('')).toEqual([]);
  });

  it('links web addresses', () => {
    expect(linkify('Map: https://example.com/trail?id=4#top and more')).toEqual([
      { text: 'Map: ' },
      { text: 'https://example.com/trail?id=4#top', href: 'https://example.com/trail?id=4#top' },
      { text: ' and more' },
    ]);
  });

  it('links addresses that start with www. over HTTPS', () => {
    expect(linkify('www.byui.edu')).toEqual([
      { text: 'www.byui.edu', href: 'https://www.byui.edu' },
    ]);
  });

  it.each([
    ['See https://example.com.', 'https://example.com', '.'],
    ['(see https://example.com)', 'https://example.com', ')'],
    ['"https://example.com/a",', 'https://example.com/a', '",'],
    [
      'https://en.wikipedia.org/wiki/Hike_(sport))',
      'https://en.wikipedia.org/wiki/Hike_(sport)',
      ')',
    ],
  ])('leaves punctuation after the address out of the link in %s', (text, address, after) => {
    const pieces = linkify(text);
    const link = pieces.findIndex((piece) => piece.href);
    expect(pieces[link]).toEqual({ text: address, href: address });
    expect(pieces[link + 1]).toEqual({ text: after });
  });

  it('keeps every character, in order', () => {
    const text = 'One https://a.example two www.b.example. Three';
    expect(
      linkify(text)
        .map((piece) => piece.text)
        .join('')
    ).toBe(text);
  });

  it.each(['javascript:alert(1)', 'ftp://example.com', 'mailto:pat@byui.edu', 'https://'])(
    'makes no link from %s',
    (text) => {
      expect(linkify(text)).toEqual([{ text }]);
    }
  );

  it('links only the address in markup, which stays text', () => {
    expect(linkify('<a href="https://example.com">x</a>')).toEqual([
      { text: '<a href="' },
      { text: 'https://example.com', href: 'https://example.com' },
      { text: '">x</a>' },
    ]);
  });
});

describe('mapsUrl', () => {
  const iPhone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15';
  const android = 'Mozilla/5.0 (Linux; Android 15; Pixel 7) AppleWebKit/537.36 Chrome/141.0';

  it('opens Apple Maps on Apple devices and Google Maps elsewhere', () => {
    expect(mapsUrl('Hart Building', iPhone)).toBe(
      'https://maps.apple.com/?q=Hart%20Building%2C%20Rexburg%2C%20ID'
    );
    expect(mapsUrl('Hart Building', android)).toBe(
      'https://www.google.com/maps/search/?api=1&query=Hart%20Building%2C%20Rexburg%2C%20ID'
    );
  });

  it("doesn't add Rexburg twice", () => {
    expect(mapsUrl('Porter Park, Rexburg', android)).toBe(
      'https://www.google.com/maps/search/?api=1&query=Porter%20Park%2C%20Rexburg'
    );
  });

  it('encodes what the place text holds', () => {
    expect(mapsUrl('Room 2 & 3 #A', '')).toContain('query=Room%202%20%26%203%20%23A%2C%20');
  });
});
