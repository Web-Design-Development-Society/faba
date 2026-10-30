import { defineConfig } from 'vitest/config';

// Unit tests cover pure logic (design document section 12.2), so they run in plain Node without
// Astro's Vite setup. Astro's getViteConfig() fails to start under Vitest 5 with the Cloudflare
// adapter.
export default defineConfig({
  test: {
    include: ['tests/unit/**/*.test.ts'],
  },
});
