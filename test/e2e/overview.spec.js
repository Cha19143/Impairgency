// §1.3's numbers, read off the running dashboard.
//
// The widget test for this screen hands OverviewScreen a UsageOverview it built
// itself. That proves the screen renders what it is given; it cannot prove the
// numbers came from Firestore. These do: the figures asserted below are the
// arithmetic of the documents seed.js wrote, fetched through the real query and
// the real rules.

import { expect, test } from '@playwright/test';
import { ADMIN, EXPECTED, clearSessions, clearSos, seedSessions, seedSos } from './seed.js';
import { open, screen, signIn } from './helpers/app.js';

test.describe.configure({ mode: 'serial' });

async function signInAsAdmin(page) {
  await open(page, '/admin');
  await signIn(page, { email: ADMIN.email, password: ADMIN.password });
  await expect(page).toHaveURL(/#\/admin\/overview$/);
}

test('the overview reports the seeded sessions, not a placeholder', async ({ page }) => {
  await signInAsAdmin(page);

  // Each of these reaches the screen a different way - a distinct-user count, a
  // row count, a sum of one event kind, and a median - so no single broken
  // query can satisfy them all at once.
  await expect(screen(page).getByText(`Active users: ${EXPECTED.activeUsers}`)).toBeVisible();
  await expect(screen(page).getByText(`Navigation sessions: ${EXPECTED.sessions}`)).toBeVisible();
  await expect(screen(page).getByText(`SOS incidents: ${EXPECTED.sosIncidents}`)).toBeVisible();
  await expect(
    screen(page).getByText(`Positioning quality: ${EXPECTED.positioningQuality}%`),
  ).toBeVisible();

  // The screen this replaced hardcoded 15.4K, 99.2% and 14ms, and looked
  // entirely convincing. A number that survives an empty database is a lie.
  await expect(screen(page).getByText('15.4K')).toHaveCount(0);
  await expect(screen(page).getByText('99.2%')).toHaveCount(0);
});

test('the detections panel counts, and says that counting is not accuracy', async ({ page }) => {
  await signInAsAdmin(page);

  await expect(
    screen(page).getByText('Counts of what the app reported, not accuracy.', { exact: false }),
  ).toBeVisible();
});

test('with no journeys, the page says why instead of showing zeroes', async ({ page }) => {
  // Journeys are recorded only for users with history on. Before, an empty
  // session_summaries collection blanked the whole page - including the
  // emergencies, which never came from there.
  //
  // The database is emptied before signing in rather than after: a reload would
  // be the obvious way to refetch, but this build does not keep a signed-in
  // session across one, so the reload would land back on the sign-in screen and
  // the test would fail for an unrelated reason.
  try {
    await clearSessions();
    await signInAsAdmin(page);

    await expect(
      screen(page).getByText('No journeys recorded in this period.', { exact: false }),
    ).toBeVisible();
    await expect(screen(page).getByText(`SOS incidents: ${EXPECTED.sosIncidents}`)).toBeVisible();
    await expect(screen(page).getByText('Positioning quality: 0%')).toHaveCount(0);
  } finally {
    await seedSessions();
  }
});

test('an empty database says so, instead of showing zeroes that read as measurements', async ({ page }) => {
  // AdminPage draws an empty state precisely so a dashboard with no data
  // cannot be mistaken for a dashboard reporting zero, and only a run against
  // the real query proves which one appears.
  try {
    await clearSessions();
    await clearSos();
    await signInAsAdmin(page);

    await expect(screen(page).getByText('Nothing recorded in the last 30 days')).toBeVisible();
    await expect(screen(page).getByText('Active users: 0')).toHaveCount(0);
    await expect(screen(page).getByText('Positioning quality: 0%')).toHaveCount(0);
  } finally {
    // Leave the emulator as the other specs expect to find it.
    await seedSessions();
    await seedSos();
  }
});
