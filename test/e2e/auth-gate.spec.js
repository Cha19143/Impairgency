// The door to the dashboard, driven in a real browser.
//
//   tool/test_e2e.sh
//
// Every other test of this screen renders it in a Flutter test harness with the
// auth callback stubbed out. These sign in for real: a browser, the shipped web
// build, Firebase Auth and Firestore on the emulators, and the same
// firestore.rules that ship. The defects below are ones the redirect rule
// documents in its own comments (lib/app/routes.dart) - they were found the
// hard way, and nothing until now could catch them coming back.

import { expect, test } from '@playwright/test';
import { ADMIN, NOT_ADMIN } from './seed.js';
import { open, passwordField, screen, signIn } from './helpers/app.js';

test('a signed-out deep link into the dashboard lands on sign-in', async ({ page }) => {
  await open(page, '/admin/health');

  await expect(page).toHaveURL(/#\/admin\/sign-in$/);
  await expect(screen(page).getByRole('heading', { name: 'Sign in' })).toBeVisible();
});

test('the mobile app is not reachable on the web build', async ({ page }) => {
  // §7's platform split: on web the app is the dashboard and nothing else.
  await open(page, '/home');

  await expect(page).toHaveURL(/#\/admin\/sign-in$/);
});

test('a wrong password says so, and does not pretend to sign in', async ({ page }) => {
  await open(page, '/admin');
  await signIn(page, { email: ADMIN.email, password: 'not-the-password' });

  await expect(
    screen(page).getByText('That email and password do not match an account.'),
  ).toBeVisible();
  await expect(page).toHaveURL(/#\/admin\/sign-in$/);
});

// Once a known defect, marked test.fail: authentication succeeded and the
// sign-in form sat there unchanged, because for a non-admin the redirect
// rightly says "stay", the route never changed, and nothing rebuilt the screen
// with who had signed in. The route now rebuilds from the session itself.
test(
  'an account that is not on the roster is told why, and not shown the form again',
  async ({ page }) => {
    await open(page, '/admin');
    await signIn(page, { email: NOT_ADMIN.email, password: NOT_ADMIN.password });

    await expect(
      screen(page).getByRole('heading', { name: 'Signed in, but not an administrator' }),
    ).toBeVisible();

    // Names the account, and prints the exact document that would grant it.
    await expect(screen(page).getByText(NOT_ADMIN.email)).toBeVisible();
    await expect(screen(page).getByText(`admins/${NOT_ADMIN.uid}`)).toBeVisible();

    // Re-offering the password form is the defect this screen exists to
    // prevent: the account is fine, the roster is the problem, and asking them
    // to type it again says neither.
    await expect(passwordField(page)).toHaveCount(0);
  },
);

test('an administrator signs in and lands on the overview', async ({ page }) => {
  await open(page, '/admin');
  await signIn(page, { email: ADMIN.email, password: ADMIN.password });

  // The defect this pins: a correct password used to redisplay the login form,
  // because the guard was right about permission and silent about where to go
  // next. Waiting on the URL rather than the button matters - sign-in resolves
  // before the redirect, which only happens after an async roster read.
  await expect(page).toHaveURL(/#\/admin\/overview$/);
  await expect(screen(page).getByRole('heading', { name: 'Overview' })).toBeVisible();
});
