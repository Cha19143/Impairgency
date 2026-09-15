import { expect } from '@playwright/test';

// Talking to a Flutter web app from a browser test.
//
// The dashboard paints to a canvas, so there is no DOM to select until Flutter
// builds its accessibility tree. The build under test asks for that tree at
// boot (see lib/main.dart) - clicking the engine's "Enable accessibility"
// placeholder is not enough on this engine: the click is accepted and the
// placeholder disappears, but no tree follows.
//
// Once it exists, the tree is ordinary HTML: headings are <h2>, buttons carry
// role="button", and text fields are real <input> elements. So the selectors
// below are the normal accessibility-first Playwright ones, and a test that
// breaks here is a test that a screen reader would also have trouble with.

/// The accessibility tree the dashboard renders into.
///
/// Scoped on purpose. Flutter also mirrors announcements into a live region
/// (`flt-announcement-polite`) that sits outside this host, so an unscoped
/// getByText can match the same sentence twice and trip Playwright's strict
/// mode - and only once the announcement has been spoken, which makes it an
/// intermittent failure rather than an honest one.
export const screen = (page) => page.locator('flt-semantics-host');

/// go_router runs on Flutter web's default hash strategy, so every route is a
/// fragment: `/#/admin/overview`, never `/admin/overview`.
export const route = (path) => `/#${path}`;

/// Opens a dashboard route and waits for the accessibility tree to exist.
export async function open(page, path = '/admin') {
  await page.goto(route(path));
  await page.locator('flt-semantics-host flt-semantics').first().waitFor();
}

/// Flutter folds a field's hint into its accessible name, so the email field is
/// labelled "Email\nyou@example.com". Matching the input type is stabler than
/// matching a name that changes whenever the placeholder copy does.
export const emailField = (page) => screen(page).locator('input[inputmode="email"]');
export const passwordField = (page) => screen(page).locator('input[type="password"]');
export const signInButton = (page) =>
  screen(page).getByRole('button', { name: 'Sign in', exact: true });

/// Types into a Flutter text field, and proves the text arrived.
///
/// Flutter only starts listening for `input` events once the framework has
/// opened a text-input connection, which happens after the field is genuinely
/// focused. Filling before that drops the text silently: the form then submits
/// empty and the auth emulator answers INVALID_EMAIL, which looks like a
/// credentials bug and is not one.
///
/// Focus arriving is not quite the same moment as the connection opening, so a
/// fill can still land in the gap and vanish. It is tried again rather than
/// failing the test: a person typing never hits this, because a keypress
/// arrives long after the connection is open.
export async function fill(field, text) {
  for (let attempt = 0; attempt < 3; attempt++) {
    await field.click();
    await expect(field).toBeFocused();
    await field.fill(text);
    try {
      await expect(field).toHaveValue(text, { timeout: 3_000 });
      return;
    } catch (error) {
      if (attempt === 2) throw error;
    }
  }
}

export async function signIn(page, { email, password }) {
  await fill(emailField(page), email);
  await fill(passwordField(page), password);
  await signInButton(page).click();
}
