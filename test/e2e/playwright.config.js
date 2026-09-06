import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',

  // One emulator and one database, so workers would race each other's data.
  // The empty-state test deletes every session summary; a second worker running
  // the overview test at that moment would fail for the wrong reason.
  workers: 1,
  fullyParallel: false,

  // CanvasKit boots slower than a DOM app, and a sign-in costs an auth round
  // trip plus a Firestore read before the redirect lands.
  timeout: 60_000,
  expect: { timeout: 15_000 },

  reporter: 'list',
  globalSetup: './global-setup.js',

  use: {
    baseURL: 'http://127.0.0.1:5050',
    // The Flutter build registers a service worker that would serve a stale
    // bundle after a rebuild. Blocking it means a run always tests what was
    // just built.
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
  },

  // Desktop only, deliberately. Flutter's engine picks MobileSemanticsEnabler
  // when the browser does not look like a desktop, and that path builds the
  // accessibility tree differently.
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
