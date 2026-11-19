// The theme chosen on Me (UI-34): only light or dark is a choice, and anything else follows the device.
import { describe, expect, it } from 'vitest';
import { themeFrom } from '../../src/lib/theme';

describe('themeFrom', () => {
  it('keeps light or dark', () => {
    expect(themeFrom('light')).toBe('light');
    expect(themeFrom('dark')).toBe('dark');
  });

  it('follows the device without a cookie, or with anything else in it', () => {
    for (const value of [undefined, '', 'device', 'Dark', 'blue', 'dark; light']) {
      expect(themeFrom(value)).toBe('device');
    }
  });
});
