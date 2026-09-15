// §1.2's user management, driven in a real browser against the emulators.
//
// Asked for by the testers: filters for blind, colour-blind and guardian
// accounts, and adding, editing and removing accounts. Adding one is the part
// only a browser can prove - it goes through a second Firebase app so the
// administrator stays signed in, which no widget test can exercise.
//
// Flutter web exposes a selectable chip as a checkbox, which is what a screen
// reader announces, so the filters are found by that role.

import { expect, test } from '@playwright/test';
import { ADMIN, authAccountExists, readDoc } from './seed.js';
import { emailField, fill, open, screen, signIn } from './helpers/app.js';

test.describe.configure({ mode: 'serial' });

const NEW = { email: 'cora@impairgency.test', name: 'Cora' };

async function openUsers(page) {
  await open(page, '/admin');
  await signIn(page, { email: ADMIN.email, password: ADMIN.password });
  await expect(page).toHaveURL(/#\/admin\/overview$/);
  await open(page, '/admin/users');
  await expect(screen(page).getByText('Anna', { exact: true })).toBeVisible();
}

test('the Guardians and Blind filters show only their accounts', async ({ page }) => {
  await openUsers(page);

  await screen(page).getByRole('checkbox', { name: /^Guardians · 1/ }).click();
  await expect(screen(page).getByText('Gina', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Ben', { exact: true })).toHaveCount(0);

  await screen(page).getByRole('checkbox', { name: /^Blind · 1/ }).click();
  await expect(screen(page).getByText('Anna', { exact: true })).toBeVisible();
  await expect(screen(page).getByText('Gina', { exact: true })).toHaveCount(0);
});

test('an account added here exists, and the administrator stays signed in', async ({ page }) => {
  await openUsers(page);

  await screen(page).getByRole('button', { name: 'Add account' }).click();
  await fill(emailField(page), NEW.email);
  await fill(screen(page).getByRole('textbox', { name: 'Name' }), NEW.name);
  await screen(page).getByRole('button', { name: 'Add account' }).last().click();

  await expect(screen(page).getByText(NEW.name, { exact: true })).toBeVisible();
  await expect(page).toHaveURL(/#\/admin\/users$/);
  expect(await authAccountExists(NEW.email)).toBe(true);
});

test('an edit changes what the table shows', async ({ page }) => {
  await openUsers(page);

  await screen(page).getByRole('button', { name: 'Actions for Ben' }).click();
  await screen(page).getByRole('menuitem', { name: 'Edit' }).click();
  const name = screen(page).getByRole('textbox', { name: 'Name' });
  await fill(name, 'Ben Santos');
  await screen(page).getByRole('button', { name: 'Save changes' }).click();

  await expect(screen(page).getByText('Ben Santos', { exact: true })).toBeVisible();
});

test('a removed account leaves the table and is marked removed', async ({ page }) => {
  await openUsers(page);

  await screen(page).getByRole('button', { name: `Actions for ${NEW.name}` }).click();
  await screen(page).getByRole('menuitem', { name: 'Remove' }).click();
  await screen(page).getByRole('button', { name: 'Remove account' }).click();

  // The row going is not enough on its own: the confirmation covered the
  // table, so its rows were out of the accessibility tree before anything was
  // deleted. Wait for the database instead.
  await expect
    .poll(async () => {
      const removed = (await readDoc('removed_accounts'))?.documents ?? [];
      if (removed.length !== 1) return 'no removal marker';
      const uid = removed[0].name.split('/').pop();
      return (await readDoc(`users/${uid}`)) === null ? 'removed' : 'profile still there';
    }, { timeout: 15_000 })
    .toBe('removed');
  await expect(
    screen(page).getByRole('button', { name: `Actions for ${NEW.name}` }),
  ).toHaveCount(0);
});
