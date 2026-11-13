// FABA's line icons (UI-02): 24 px drawings in one stroke weight, for src/components/Icon.astro.
// They're inline SVG, so there's no icon font, no request and no framework (ADR-011). The
// categories' icons have the names the database gives them (design document section 10.3).

const DOT = (x: number, y: number) =>
  `<circle cx="${x}" cy="${y}" r="1.25" fill="currentColor" stroke="none"/>`;

export const ICONS = {
  // The app's frame.
  search: '<circle cx="11" cy="11" r="7"/><path d="m16.5 16.5 4.5 4.5"/>',
  back: '<path d="m15 5-7 7 7 7"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  home: '<path d="M3 11 12 3.5 21 11"/><path d="M5.5 9.5V20h13V9.5"/><path d="M10 20v-5h4v5"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  // What, when, where and who.
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
  pin: '<path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21Z"/><circle cx="12" cy="9.5" r="2.5"/>',
  people:
    '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.3a6.5 6.5 0 0 1 3.5 5.7"/>',
  // Alerts.
  bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15Z"/><path d="M10 21h4"/>',
  check: '<path d="m4 12.5 5.5 5.5L20 6.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  arrows: '<path d="M4 8h15m-4-4 4 4-4 4M20 16H5m4-4-4 4 4 4"/>',
  rotate: '<path d="M3 12a9 9 0 1 0 2.6-6.4L3 8"/><path d="M3 3v5h5"/>',
  chat: '<path d="M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9l-5 4v-4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/>',
  megaphone:
    '<path d="M3 10v4a1 1 0 0 0 1 1h3l8 4V5L7 9H4a1 1 0 0 0-1 1Z"/><path d="M18.5 9a4 4 0 0 1 0 6M7 15l1.5 5H11l-1-4.5"/>',
  'user-plus':
    '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6"/>',
  'user-minus': '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 11h6"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3M15 8l2 2"/>',
  flag: '<path d="M5 21V4h11l-2 4 2 4H5"/>',
  // Categories.
  mountain: '<path d="m2 20 7-12 4 6 2.5-3.5L22 20Z"/><path d="m7.2 11 1.8 1.5 1.8-1.5"/>',
  ball: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3v18M5.6 5.6c2.8 3.4 2.8 9.4 0 12.8M18.4 5.6c-2.8 3.4-2.8 9.4 0 12.8"/>',
  dice: `<rect x="4" y="4" width="16" height="16" rx="3"/>${DOT(9, 9)}${DOT(15, 9)}${DOT(12, 12)}${DOT(9, 15)}${DOT(15, 15)}`,
  utensils: '<path d="M4.5 3v5a2.5 2.5 0 0 0 5 0V3M7 3v18M17 21V3c-2.5 1.5-3.5 4-3.5 8H17"/>',
  palette: `<path d="M12 3a9 9 0 1 0 0 18c1.4 0 2-1 2-2s-.6-1.4-.6-2.3c0-1 .8-1.7 1.8-1.7H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8Z"/>${DOT(7.5, 11)}${DOT(10, 7)}${DOT(15, 7.5)}`,
  book: '<path d="M3 5.5C5.5 4 9 4 12 6c3-2 6.5-2 9-.5V19c-2.5-1.5-6-1.5-9 .5-3-2-6.5-2-9-.5Z"/><path d="M12 6v13.5"/>',
  'heart-hand':
    '<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10Z"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-5.5-3.5-9s1-6.5 3.5-9Z"/>',
  sparkle:
    '<path d="m12 3 1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8Z"/><path d="m19 15.5.6 1.9 1.9.6-1.9.6-.6 1.9-.6-1.9-1.9-.6 1.9-.6Z"/>',
} as const;

export type IconName = keyof typeof ICONS;

/** True when `name` is one of FABA's icons, such as a category's icon from the database. */
export function isIcon(name: string): name is IconName {
  return Object.hasOwn(ICONS, name);
}
