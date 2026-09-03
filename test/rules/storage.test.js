/**
 * Storage security rules tests.
 *
 * These rules cannot be deployed: a Cloud Storage bucket requires the Blaze
 * plan and this project has no budget. They can still be *proved*, because the
 * Storage emulator provisions its own bucket locally and costs nothing. An
 * untested rules file is a claim; this makes it a fact.
 *
 * The defect each case guards against is named in the test.
 *
 *   firebase emulators:exec --only firestore,storage --project demo-impairgency \
 *     "npm --prefix test/rules test"
 */
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'mocha';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

const OWNER = 'vi-user-1';
const OTHER = 'guardian-1';

const MB = 1024 * 1024;

let env;

/** A payload of a given size; contents are irrelevant to every rule here. */
const payload = (size) => new Uint8Array(size);

const ownerPath = `users/${OWNER}/scan.jpg`;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-impairgency',
    storage: { rules: readFileSync('../../storage.rules', 'utf8') },
  });
});

after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearStorage();
  // Seeded past the rules so read cases test reads, not writes.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), ownerPath), payload(64));
  });
});

describe('a user own files', () => {
  it('the owner reads their own file', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertSucceeds(getBytes(ref(storage, ownerPath)));
  });

  it('the owner writes their own file', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, `users/${OWNER}/new.jpg`), payload(64)),
    );
  });

  // `request.resource` is null on a delete just as it is on a read, so a size
  // cap attached to `write` locks the owner out of deleting their own files.
  it('the owner deletes their own file', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertSucceeds(deleteObject(ref(storage, ownerPath)));
  });
});

describe('everyone else', () => {
  // The previous project's rules paired a blanket deny with `allow read: if
  // true` on /users/**. Firebase grants on any matching allow, so every user
  // file was world-readable. This is that defect, as a test.
  it('an unauthenticated client is refused a read', async () => {
    const storage = env.unauthenticatedContext().storage();
    await assertFails(getBytes(ref(storage, ownerPath)));
  });

  it('another signed-in user is refused a read', async () => {
    const storage = env.authenticatedContext(OTHER).storage();
    await assertFails(getBytes(ref(storage, ownerPath)));
  });

  it('another signed-in user is refused a write', async () => {
    const storage = env.authenticatedContext(OTHER).storage();
    await assertFails(
      uploadBytes(ref(storage, `users/${OWNER}/planted.jpg`), payload(64)),
    );
  });

  it('another signed-in user is refused a delete', async () => {
    const storage = env.authenticatedContext(OTHER).storage();
    await assertFails(deleteObject(ref(storage, ownerPath)));
  });

  it('a path outside /users is refused entirely', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertFails(
      uploadBytes(ref(storage, 'public/anything.jpg'), payload(64)),
    );
  });
});

describe('the size cap', () => {
  it('accepts a file under 25 MB', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, `users/${OWNER}/small.jpg`), payload(MB)),
    );
  });

  it('refuses a file over 25 MB', async () => {
    const storage = env.authenticatedContext(OWNER).storage();
    await assertFails(
      uploadBytes(ref(storage, `users/${OWNER}/huge.jpg`), payload(26 * MB)),
    );
  }).timeout(60_000);
});
