// How categories look on cards. The database names each category's icon and color token
// (design document section 10.3). These are placeholders until the design tokens and icons exist
// (Iteration 1 task UX-4).

const ICONS: Record<string, string> = {
  mountain: '⛰️',
  ball: '🏀',
  dice: '🎲',
  utensils: '🍴',
  palette: '🎨',
  book: '📚',
  'heart-hand': '🤝',
  people: '👪',
  globe: '🌐',
  sparkle: '✨',
};

const COLORS: Record<string, string> = {
  'category-outdoors': '#2e7d32',
  'category-sports': '#1565c0',
  'category-games': '#6a1b9a',
  'category-food': '#e65100',
  'category-arts': '#c2185b',
  'category-learning': '#00838f',
  'category-service': '#c62828',
  'category-family': '#f9a825',
  'category-online': '#455a64',
  'category-other': '#616161',
};

/** The emoji for a category's icon name, and the color for its color token. */
export function categoryLook(category: { icon: string; color_token: string }) {
  return {
    icon: ICONS[category.icon] ?? ICONS.sparkle,
    color: COLORS[category.color_token] ?? COLORS['category-other'],
  };
}
