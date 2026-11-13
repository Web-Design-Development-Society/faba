// How categories look on cards. The database names each category's icon and color token
// (design document section 10.3), and each icon is one of FABA's line icons (UI-02).
import { isIcon, type IconName } from './icons';

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

/** The line icon for a category's icon name, and the color for its color token. */
export function categoryLook(category: { icon: string; color_token: string }): {
  icon: IconName;
  color: string;
} {
  return {
    icon: isIcon(category.icon) ? category.icon : 'sparkle',
    color: COLORS[category.color_token] ?? COLORS['category-other'],
  };
}
