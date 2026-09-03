/**
 * Security rules tests.
 *
 * The previous project had no rules file in version control, so there was
 * nothing to test and no way to review who could read a user's emergency
 * contacts. Each case below is a question someone should be able to ask of this
 * project and get an answer to.
 *
 *   firebase emulators:exec --only firestore --project demo-impairgency \
 *     "npm --prefix test/rules test"
 */
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'mocha';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const VI = 'vi-user-1';
const GUARDIAN = 'guardian-1';
const STRANGER = 'guardian-2';
const ADMIN = 'admin-1';

let env;

/** Deterministic pairing id, matching the rule: {guardianUid}_{viUserId}. */
const pairingId = (guardian, vi) => `${guardian}_${vi}`;

const hoursFromNow = (h) => new Date(Date.now() + h * 3600_000);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-impairgency',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8') },
  });
});

after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', VI), {
      uid: VI,
      role: 'vi',
      email: 'vi@example.com',
      consent: { location: false, recording: false, faces: false },
    });
    await setDoc(doc(db, 'users', GUARDIAN), {
      uid: GUARDIAN,
      role: 'guardian',
      email: 'guardian@example.com',
    });
    await setDoc(doc(db, 'pairings', pairingId(GUARDIAN, VI)), {
      guardianId: GUARDIAN,
      viUserId: VI,
    });
    await setDoc(doc(db, 'location_history', VI, 'fixes', 'fix-1'), {
      lat: 14.79,
      lng: 120.92,
      at: serverTimestamp(),
    });
    await setDoc(doc(db, 'otp_verification', 'vi@example.com'), {
      code: '123456',
    });
  });
});

const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();
const asAdmin = () => as(ADMIN, { admin: true });
const anon = () => env.unauthenticatedContext().firestore();

describe('user documents', () => {
  it('an owner reads and writes their own document', async () => {
    const db = as(VI);
    await assertSucceeds(getDoc(doc(db, 'users', VI)));
    await assertSucceeds(
      updateDoc(doc(db, 'users', VI), { displayName: 'Bob' }),
    );
  });

  it('a stranger cannot read someone else', async () => {
    await assertFails(getDoc(doc(as(STRANGER), 'users', VI)));
  });

  it('an anonymous visitor cannot read anything', async () => {
    await assertFails(getDoc(doc(anon(), 'users', VI)));
  });

  it('a paired guardian can read the user they watch over', async () => {
    await assertSucceeds(getDoc(doc(as(GUARDIAN), 'users', VI)));
  });

  it('an unpaired guardian cannot', async () => {
    await assertFails(getDoc(doc(as(STRANGER), 'users', VI)));
  });

  it('a client cannot make itself an admin', async () => {
    // A role field the client can write is not a role. Admin is a custom claim.
    await assertFails(updateDoc(doc(as(VI), 'users', VI), { role: 'admin' }));
    await assertFails(updateDoc(doc(as(VI), 'users', VI), { admin: true }));
  });

  it('a new account cannot be created with the admin role', async () => {
    const db = as('new-user');
    await assertFails(
      setDoc(doc(db, 'users', 'new-user'), { uid: 'new-user', role: 'admin' }),
    );
    await assertSucceeds(
      setDoc(doc(db, 'users', 'new-user'), { uid: 'new-user', role: 'vi' }),
    );
  });

  it('a user cannot create a document under someone else id', async () => {
    await assertFails(
      setDoc(doc(as('impostor'), 'users', VI), { uid: VI, role: 'vi' }),
    );
  });

  it('an admin claim can read any user', async () => {
    await assertSucceeds(getDoc(doc(asAdmin(), 'users', VI)));
  });
});

describe('location history', () => {
  const fix = (db) => doc(db, 'location_history', VI, 'fixes', 'fix-1');

  it('the owner always reads their own fixes', async () => {
    await assertSucceeds(getDoc(fix(as(VI))));
  });

  it('a paired guardian is refused while location consent is off', async () => {
    // Revoking consent in the app has to be enforced by the server, not just by
    // hiding a button.
    await assertFails(getDoc(fix(as(GUARDIAN))));
  });

  it('a paired guardian may read once consent is on', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        'consent.location': true,
      });
    });
    await assertSucceeds(getDoc(fix(as(GUARDIAN))));
  });

  it('an unpaired guardian is refused even with consent on', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        'consent.location': true,
      });
    });
    await assertFails(getDoc(fix(as(STRANGER))));
  });

  it('nobody can rewrite history, not even the owner', async () => {
    await assertFails(updateDoc(fix(as(VI)), { lat: 0 }));
  });
});

describe('pairing codes', () => {
  const CODE = '7K429P';
  const codeRef = (db) => doc(db, 'pairing_codes', CODE);

  const seedCode = (extra = {}) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes', CODE), {
        ownerId: VI,
        usedBy: null,
        expiresAt: hoursFromNow(1),
        ...extra,
      });
    });

  it('the owner can issue one', async () => {
    await assertSucceeds(
      setDoc(codeRef(as(VI)), {
        ownerId: VI,
        usedBy: null,
        expiresAt: hoursFromNow(1),
      }),
    );
  });

  it('nobody can issue a code on behalf of someone else', async () => {
    await assertFails(
      setDoc(codeRef(as(STRANGER)), {
        ownerId: VI,
        usedBy: null,
        expiresAt: hoursFromNow(1),
      }),
    );
  });

  it('a guardian can redeem a valid one', async () => {
    await seedCode();
    await assertSucceeds(
      updateDoc(codeRef(as(GUARDIAN)), { usedBy: GUARDIAN, ownerId: VI }),
    );
  });

  it('a used code cannot be redeemed twice', async () => {
    await seedCode({ usedBy: GUARDIAN });
    await assertFails(
      updateDoc(codeRef(as(STRANGER)), { usedBy: STRANGER, ownerId: VI }),
    );
  });

  it('an expired code is refused', async () => {
    await seedCode({ expiresAt: hoursFromNow(-1) });
    await assertFails(
      updateDoc(codeRef(as(GUARDIAN)), { usedBy: GUARDIAN, ownerId: VI }),
    );
  });

  it('a redeemer cannot reassign the code to a different owner', async () => {
    await seedCode();
    await assertFails(
      updateDoc(codeRef(as(GUARDIAN)), {
        usedBy: GUARDIAN,
        ownerId: STRANGER,
      }),
    );
  });

  it('only the owner can delete their code', async () => {
    await seedCode();
    await assertFails(deleteDoc(codeRef(as(STRANGER))));
    await assertSucceeds(deleteDoc(codeRef(as(VI))));
  });
});

describe('pairings', () => {
  it('a guardian cannot forge a pairing under a mismatched id', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), 'pairings', 'wrong-id'), {
        guardianId: STRANGER,
        viUserId: VI,
      }),
    );
  });

  it('a guardian cannot create a pairing naming someone else', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), 'pairings', pairingId(GUARDIAN, VI)), {
        guardianId: GUARDIAN,
        viUserId: VI,
      }),
    );
  });

  it('either side can break the link', async () => {
    await assertSucceeds(
      deleteDoc(doc(as(VI), 'pairings', pairingId(GUARDIAN, VI))),
    );
  });

  it('cannot be self-issued without redeeming a code', async () => {
    // The hole: without this, any signed-in account writes
    // pairings/{ownUid}_{victimId} and is thereafter a "paired guardian" with
    // read access to that user's document - and to their location, once the
    // user turns location consent on for someone they actually trust.
    await assertFails(
      setDoc(doc(as(STRANGER), 'pairings', pairingId(STRANGER, VI)), {
        guardianId: STRANGER,
        viUserId: VI,
      }),
    );
  });

  it('is allowed only for a code that user issued and this guardian redeemed',
    async () => {
      const CODE = 'HJ42KX';
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'pairing_codes', CODE), {
          ownerId: VI,
          usedBy: STRANGER,
          expiresAt: hoursFromNow(1),
        });
      });
      // Redeemed by STRANGER, so GUARDIAN cannot ride on it.
      await assertFails(
        setDoc(doc(as(GUARDIAN), 'pairings', pairingId(GUARDIAN, VI)), {
          guardianId: GUARDIAN,
          viUserId: VI,
          code: CODE,
        }),
      );
      await assertSucceeds(
        setDoc(doc(as(STRANGER), 'pairings', pairingId(STRANGER, VI)), {
          guardianId: STRANGER,
          viUserId: VI,
          code: CODE,
        }),
      );
    });

  it('cannot reuse a code issued by a different user', async () => {
    const CODE = 'HJ42KX';
    await env.withSecurityRulesDisabled(async (ctx) => {
      // A code STRANGER issued for themselves, redeemed by themselves, does
      // not let them pair with VI.
      await setDoc(doc(ctx.firestore(), 'pairing_codes', CODE), {
        ownerId: STRANGER,
        usedBy: STRANGER,
        expiresAt: hoursFromNow(1),
      });
    });
    await assertFails(
      setDoc(doc(as(STRANGER), 'pairings', pairingId(STRANGER, VI)), {
        guardianId: STRANGER,
        viUserId: VI,
        code: CODE,
      }),
    );
  });

  it('a pairing cannot be edited, only made or broken', async () => {
    await assertFails(
      updateDoc(doc(as(GUARDIAN), 'pairings', pairingId(GUARDIAN, VI)), {
        viUserId: 'someone-else',
      }),
    );
  });
});

describe('push tokens', () => {
  const tokenRef = (db, uid = VI) =>
    doc(db, 'users', uid, 'push_tokens', 'device-token-abc');

  it('the owner registers their own device', async () => {
    await assertSucceeds(
      setDoc(tokenRef(as(VI)), { token: 'abc', platform: 'ios' }),
    );
  });

  it('nobody else can read them, not even a paired guardian', async () => {
    // A token another account can read is a token another account can send
    // notifications to. The sending function uses the Admin SDK and bypasses
    // rules, so no client needs read access at all.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(tokenRef(ctx.firestore()), { token: 'abc' });
    });
    await assertFails(getDoc(tokenRef(as(GUARDIAN))));
    await assertFails(getDoc(tokenRef(as(STRANGER))));
    await assertFails(getDoc(tokenRef(anon())));
  });

  it('nobody else can register a device against your account', async () => {
    await assertFails(setDoc(tokenRef(as(STRANGER)), { token: 'evil' }));
  });
});

describe('the whole guardian onboarding, end to end', () => {
  // Exercises exactly what PairingRepository does, in the order it does it,
  // against the real rules. If this passes, a guardian can actually get in -
  // which is the thing the submitted design had no screen for at all.
  it('issue, redeem, pair, then read', async () => {
    const CODE = 'FH29MR47';

    // 1. The user issues a code.
    await assertSucceeds(
      setDoc(doc(as(VI), 'pairing_codes', CODE), {
        ownerId: VI,
        usedBy: null,
        expiresAt: hoursFromNow(0.5),
      }),
    );

    // 2. A guardian who has never met this user before cannot read them yet.
    await assertFails(getDoc(doc(as(STRANGER), 'users', VI)));

    // 3. They look the code up - any signed-in account may, which is why the
    //    code space has to be large.
    await assertSucceeds(getDoc(doc(as(STRANGER), 'pairing_codes', CODE)));

    // 4. They redeem it.
    await assertSucceeds(
      updateDoc(doc(as(STRANGER), 'pairing_codes', CODE), {
        usedBy: STRANGER,
        ownerId: VI,
      }),
    );

    // 5. And only now can they create the pairing.
    await assertSucceeds(
      setDoc(doc(as(STRANGER), 'pairings', pairingId(STRANGER, VI)), {
        guardianId: STRANGER,
        viUserId: VI,
        code: CODE,
      }),
    );

    // 6. Which is what grants the read.
    await assertSucceeds(getDoc(doc(as(STRANGER), 'users', VI)));

    // 7. But not the location, until consent is given separately. Being
    //    someone's guardian and being allowed to track them are two decisions.
    await assertFails(
      getDoc(doc(as(STRANGER), 'location_history', VI, 'fixes', 'fix-1')),
    );

    // 8. And the code is spent - nobody else can ride in behind them.
    await assertFails(
      updateDoc(doc(as(GUARDIAN), 'pairing_codes', CODE), {
        usedBy: GUARDIAN,
        ownerId: VI,
      }),
    );
  });

  it('the user can cut the link afterwards', async () => {
    await assertSucceeds(
      deleteDoc(doc(as(VI), 'pairings', pairingId(GUARDIAN, VI))),
    );
    await assertFails(getDoc(doc(as(GUARDIAN), 'users', VI)));
  });
});

describe('one-time login codes', () => {
  it('no client can read them, signed in or not', async () => {
    // A collection of live OTPs that any session can read is an account
    // takeover. These are issued and checked in functions/ with the Admin SDK.
    const ref = (db) => doc(db, 'otp_verification', 'vi@example.com');
    await assertFails(getDoc(ref(anon())));
    await assertFails(getDoc(ref(as(VI))));
    await assertFails(getDoc(ref(as(STRANGER))));
    await assertFails(getDoc(ref(asAdmin())));
  });

  it('no client can write them either', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), 'otp_verification', 'vi@example.com'), {
        code: '000000',
      }),
    );
  });
});

describe('everything else', () => {
  it('is denied by default', async () => {
    await assertFails(getDoc(doc(as(VI), 'app_counters', 'devices')));
    await assertFails(setDoc(doc(as(VI), 'anything', 'at-all'), { x: 1 }));
  });
});
