// System health's Emergencies panel, against the real sos_events and rules.
//
// A tester fired an SOS and it never reached the dashboard: nothing on it read
// sos_events. These rows come from the documents seed.js wrote, read through
// the admin query; Mark resolved goes through the rule that lets an
// administrator change three fields and nothing else.

import { expect, test } from '@playwright/test';
import { ADMIN, SOS, readDoc, seedSos } from './seed.js';
import { open, screen, signIn } from './helpers/app.js';

test.describe.configure({ mode: 'serial' });

async function openHealth(page) {
  await open(page, '/admin');
  await signIn(page, { email: ADMIN.email, password: ADMIN.password });
  await expect(page).toHaveURL(/#\/admin\/overview$/);
  await open(page, '/admin/health');
  await expect(screen(page).getByText('Called Mum', { exact: true })).toBeVisible();
}

test('each SOS is listed with who, where, and its status', async ({ page }) => {
  await openHealth(page);

  await expect(screen(page).getByText('Anna', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Ben', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Your location was sent.', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Active', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Cancelled', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Emergencies: 1', { exact: false })).toBeVisible();
});

test('Mark resolved flips the row, and records who did it', async ({ page }) => {
  try {
    await openHealth(page);

    await screen(page).getByRole('button', { name: 'Mark resolved' }).click();
    await expect(screen(page).getByText('Resolved by admin', { exact: true })).toBeVisible();
    await expect(screen(page).getByRole('button', { name: 'Mark resolved' })).toHaveCount(0);

    const doc = await readDoc(`sos_events/${SOS.active}`);
    expect(doc.fields.resolvedBy.stringValue).toBe(ADMIN.uid);
    expect(doc.fields.status.stringValue).toBe('resolved');
    expect(doc.fields.userId.stringValue).toBe('vi-anna');
  } finally {
    await seedSos();
  }
});
