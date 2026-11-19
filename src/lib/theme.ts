// The theme a member chose on Me (UI-34): Match device, Light or Dark. It's kept on the device in a
// cookie, so the server draws each page in it and a page never shows the other theme first.
// Without one, FABA follows the device's own setting (UI-33).

export const THEMES = ['device', 'light', 'dark'] as const;
export type Theme = (typeof THEMES)[number];

/** The cookie that keeps a chosen Light or Dark. Match device is no cookie. */
export const THEME_COOKIE = 'faba-theme';

/** The browser bar's color in each theme. */
export const THEME_COLOR = { light: '#f4f7fb', dark: '#0f141b' } as const;

/** The theme a cookie's value chose. Anything but light or dark is Match device. */
export function themeFrom(value: string | undefined): Theme {
  return value === 'light' || value === 'dark' ? value : 'device';
}
