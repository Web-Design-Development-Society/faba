import { defineConfig, devices } from '@playwright/test';

// End-to-end and accessibility tests (FND-07, design document section 12.4). They need local
// Supabase running and seeded, and .dev.vars written. See CONTRIBUTING.md.

// Not 4321, so the tests never reuse a dev server that's already running other code.
const port = 4329;

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [[process.env.CI ? 'github' : 'list'], ['html', { open: 'never' }]],
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  // The sizes in section 11.5. iPhone SE runs in WebKit, which stands in for Safari.
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
    { name: 'iphone-se', use: { ...devices['iPhone SE'] } },
  ],
  // The built Worker on workerd, as it's deployed. --ignore-lock keeps it in the foreground,
  // apart from any other preview server.
  webServer: {
    command: `npm run build && npm run preview -- --port ${port} --ignore-lock`,
    url: `http://localhost:${port}/api/health`,
    timeout: 120_000,
  },
});
