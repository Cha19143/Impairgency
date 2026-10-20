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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  Bytes,
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
      consent: {
        location: false,
        history: false,
        recording: false,
        faces: false,
      },
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
/** Admin is membership of the `admins` collection, seeded past the rules. */
const asAdmin = () => as(ADMIN);
const makeAdmin = () =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'admins', ADMIN), { grantedAt: 'seed' });
  });
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

  it('an admin on the roster can read any user', async () => {
    await makeAdmin();
    await assertSucceeds(getDoc(doc(asAdmin(), 'users', VI)));
  });

  it('an account not on the roster is not an admin', async () => {
    // No admins document, so isAdmin() is false however the client behaves.
    await assertFails(getDoc(doc(asAdmin(), 'users', VI)));
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

describe('recording history is a separate consent from sharing location', () => {
  const fix = (db, id = 'new-fix') =>
    doc(db, 'location_history', VI, 'fixes', id);

  const grant = (key) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        [`consent.${key}`]: true,
      });
    });

  it('the app cannot record anything until history consent is on', async () => {
    // Gated on the server, so revoking it stops the recording rather than
    // hiding a switch in the UI.
    await assertFails(setDoc(fix(as(VI)), { lat: 1, lng: 2 }));
  });

  it('it can record once history consent is on', async () => {
    await grant('history');
    await assertSucceeds(setDoc(fix(as(VI)), { lat: 1, lng: 2 }));
  });

  it('location consent alone does not permit recording', async () => {
    // Letting a guardian see where you are is not agreeing to be logged.
    await grant('location');
    await assertFails(setDoc(fix(as(VI)), { lat: 1, lng: 2 }));
  });

  it('history consent alone does not let a guardian read it', async () => {
    // And agreeing to be logged is not agreeing to be watched.
    await grant('history');
    await assertFails(
      getDoc(doc(as(GUARDIAN), 'location_history', VI, 'fixes', 'fix-1')),
    );
  });

  it('nobody else can record against your account', async () => {
    await grant('history');
    await assertFails(setDoc(fix(as(STRANGER)), { lat: 1, lng: 2 }));
  });

  it('history is append-only', async () => {
    await grant('history');
    await assertFails(
      updateDoc(doc(as(VI), 'location_history', VI, 'fixes', 'fix-1'),
        { lat: 0 }),
    );
  });

  it('can always be deleted, consent or not', async () => {
    // "What the app has learned" must be able to forget, and revoking consent
    // must not lock the record in place.
    await assertSucceeds(
      deleteDoc(doc(as(VI), 'location_history', VI, 'fixes', 'fix-1')),
    );
  });
});

describe('session events — the review timeline', () => {
  const ev = (db, id = 'ev1') =>
    doc(db, 'location_history', VI, 'events', id);

  const grantHistory = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        'consent.history': true,
      });
    });

  it('follows the same consent as the fixes it is stamped against', async () => {
    await assertFails(setDoc(ev(as(VI)), { kind: 'obstacleDetected' }));
    await grantHistory();
    await assertSucceeds(setDoc(ev(as(VI)), { kind: 'obstacleDetected' }));
  });

  it('is readable by the user and by an admin', async () => {
    await grantHistory();
    await setDoc(ev(as(VI)), { kind: 'stairsDetected' });
    await assertSucceeds(getDoc(ev(as(VI))));
    await makeAdmin();
    await assertSucceeds(getDoc(ev(asAdmin())));
  });

  it('is not readable by a paired guardian', async () => {
    // §3 grants a guardian location and emergency alerts, not a feed of
    // everything the user walked past.
    await grantHistory();
    await setDoc(ev(as(VI)), { kind: 'textRead', detail: 'medicine bottle' });
    await assertFails(getDoc(ev(as(GUARDIAN))));
  });

  it('is append-only', async () => {
    await grantHistory();
    await setDoc(ev(as(VI)), { kind: 'obstacleDetected' });
    await assertFails(updateDoc(ev(as(VI)), { kind: 'sosFired' }));
  });

  it('can be deleted by the user regardless of consent', async () => {
    await grantHistory();
    await setDoc(ev(as(VI)), { kind: 'obstacleDetected' });
    await assertSucceeds(deleteDoc(ev(as(VI))));
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
    await makeAdmin();
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

describe('invitations — managing accounts without knowing passwords', () => {
  const INVITE = 'newuser@example.com';

  it('only an admin can issue one', async () => {
    await assertFails(
      setDoc(doc(as(VI), 'user_invites', INVITE), { role: 'vi' }),
    );
    await makeAdmin();
    await assertSucceeds(
      setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'vi' }),
    );
  });

  it('the invited person can read their own', async () => {
    await makeAdmin();
    await setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'guardian' });

    const invitee = env
      .authenticatedContext('newbie', {
        email: 'NewUser@Example.com',
        email_verified: true,
      })
      .firestore();
    // Their token's email is mixed case; the document id is lowercased.
    await assertSucceeds(getDoc(doc(invitee, 'user_invites', INVITE)));
  });

  it('an account that only claims the address cannot read it', async () => {
    // Making an account with someone else's email is free; confirming it is
    // not. The tester's made-up address would otherwise have been enough.
    await makeAdmin();
    await setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'guardian' });

    const claimant = env
      .authenticatedContext('claimant', { email: INVITE, email_verified: false })
      .firestore();
    await assertFails(getDoc(doc(claimant, 'user_invites', INVITE)));
  });

  it('nobody can read an invitation meant for someone else', async () => {
    await makeAdmin();
    await setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'vi' });

    const other = env
      .authenticatedContext('other', { email: 'other@example.com' })
      .firestore();
    await assertFails(getDoc(doc(other, 'user_invites', INVITE)));
    await assertFails(getDoc(doc(anon(), 'user_invites', INVITE)));
  });

  it('the invited person cannot edit their own role', async () => {
    // Otherwise an invitation to be a guardian becomes an invitation to be an
    // administrator.
    await makeAdmin();
    await setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'guardian' });

    const invitee = env
      .authenticatedContext('newbie', { email: INVITE })
      .firestore();
    await assertFails(
      updateDoc(doc(invitee, 'user_invites', INVITE), { role: 'admin' }),
    );
  });

  it('an admin can withdraw one', async () => {
    await makeAdmin();
    await setDoc(doc(asAdmin(), 'user_invites', INVITE), { role: 'vi' });
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'user_invites', INVITE)));
  });
});

describe('session summaries — the admin-readable aggregate', () => {
  const grantHistory = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        'consent.history': true,
      });
    });

  const summary = (extra = {}) => ({
    userId: VI,
    sessionId: 's1',
    minutes: 14,
    metres: 1200,
    eventCounts: { obstacleDetected: 3 },
    discardedFraction: 0.02,
    concernCount: 0,
    placeLabels: ['Home'],
    ...extra,
  });

  it('needs the same history consent as the data it summarises', async () => {
    await assertFails(
      setDoc(doc(as(VI), 'session_summaries', 'sum1'), summary()),
    );
    await grantHistory();
    await assertSucceeds(
      setDoc(doc(as(VI), 'session_summaries', 'sum1'), summary()),
    );
  });

  it('refuses anything carrying a coordinate', async () => {
    // The property the whole design rests on, enforced by the server rather
    // than trusted to the client type that writes it.
    await grantHistory();
    for (const leak of [
      { lat: 14.79 },
      { lng: 120.92 },
      { latitude: 14.79 },
      { longitude: 120.92 },
      { path: [{ lat: 14.79, lng: 120.92 }] },
      { fixes: ['14.79,120.92'] },
    ]) {
      await assertFails(
        setDoc(doc(as(VI), 'session_summaries', 'leak'), summary(leak)),
        `should refuse ${JSON.stringify(leak)}`,
      );
    }
  });

  it('cannot be written on someone else behalf', async () => {
    await grantHistory();
    await assertFails(
      setDoc(doc(as(STRANGER), 'session_summaries', 'sum2'), summary()),
    );
  });

  it('is readable by its owner and by an admin, not by others', async () => {
    await grantHistory();
    await setDoc(doc(as(VI), 'session_summaries', 'sum1'), summary());

    await assertSucceeds(getDoc(doc(as(VI), 'session_summaries', 'sum1')));
    await makeAdmin();
    await assertSucceeds(getDoc(doc(asAdmin(), 'session_summaries', 'sum1')));
    await assertFails(getDoc(doc(as(STRANGER), 'session_summaries', 'sum1')));
    await assertFails(getDoc(doc(as(GUARDIAN), 'session_summaries', 'sum1')));
  });

  it('is append-only', async () => {
    await grantHistory();
    await setDoc(doc(as(VI), 'session_summaries', 'sum1'), summary());
    await assertFails(
      updateDoc(doc(as(VI), 'session_summaries', 'sum1'), { minutes: 0 }),
    );
  });

  it('can be deleted by its owner', async () => {
    await grantHistory();
    await setDoc(doc(as(VI), 'session_summaries', 'sum1'), summary());
    await assertSucceeds(deleteDoc(doc(as(VI), 'session_summaries', 'sum1')));
  });
});

describe('SOS records', () => {
  const event = (extra = {}) => ({
    userId: VI,
    cancelled: false,
    status: 'active',
    locationSummary: 'Your location was sent.',
    lat: 14.79,
    lng: 120.92,
    at: serverTimestamp(),
    ...extra,
  });
  const seed = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'sos_events', 'e1'), event());
    });

  it('are written by their owner, under an id chosen before the call', async () => {
    await assertSucceeds(setDoc(doc(as(VI), 'sos_events', 'e1'), event()));
    await assertFails(
      setDoc(doc(as(STRANGER), 'sos_events', 'e2'), event()),
    );
  });

  it('are read by the owner, a paired guardian and an admin - nobody else', async () => {
    await seed();
    await makeAdmin();
    await assertSucceeds(getDoc(doc(as(VI), 'sos_events', 'e1')));
    await assertSucceeds(getDoc(doc(as(GUARDIAN), 'sos_events', 'e1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'sos_events', 'e1')));
    await assertFails(getDoc(doc(as(STRANGER), 'sos_events', 'e1')));
  });

  it('the dashboard can list every one, newest first', async () => {
    await seed();
    await makeAdmin();
    await assertSucceeds(
      getDocs(query(collection(asAdmin(), 'sos_events'), orderBy('at', 'desc'))),
    );
    await assertFails(
      getDocs(query(collection(as(STRANGER), 'sos_events'), orderBy('at', 'desc'))),
    );
  });

  it('the owner marks one resolved after the call', async () => {
    await seed();
    await assertSucceeds(
      updateDoc(doc(as(VI), 'sos_events', 'e1'), {
        status: 'resolved',
        resolvedBy: 'user',
        resolvedAt: serverTimestamp(),
      }),
    );
  });

  it('an admin marks one resolved, and changes nothing else', async () => {
    await seed();
    await makeAdmin();
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'sos_events', 'e1'), {
        status: 'resolved',
        resolvedBy: ADMIN,
        resolvedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'sos_events', 'e1'), { lat: 0 }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'sos_events', 'e1'), { userId: STRANGER }),
    );
  });

  it('nobody moves one onto someone else, or deletes it', async () => {
    await seed();
    await assertFails(
      updateDoc(doc(as(VI), 'sos_events', 'e1'), { userId: STRANGER }),
    );
    await assertFails(
      updateDoc(doc(as(GUARDIAN), 'sos_events', 'e1'), { status: 'resolved' }),
    );
    await assertFails(deleteDoc(doc(as(VI), 'sos_events', 'e1')));
  });
});

describe('the admin roster', () => {
  it('cannot be joined by the client that wants to join it', async () => {
    // The whole point: this replaces a custom claim, so it has to be exactly as
    // unreachable as one.
    await assertFails(setDoc(doc(as(VI), 'admins', VI), { grantedAt: 'now' }));
    await assertFails(setDoc(doc(asAdmin(), 'admins', STRANGER), {}));
  });

  it('cannot be granted by an existing admin from the app either', async () => {
    await makeAdmin();
    await assertFails(setDoc(doc(asAdmin(), 'admins', STRANGER), {}));
  });

  it('is not enumerable by a signed-in stranger', async () => {
    await makeAdmin();
    await assertFails(getDoc(doc(as(STRANGER), 'admins', ADMIN)));
    await assertSucceeds(getDoc(doc(asAdmin(), 'admins', ADMIN)));
  });

  it('cannot be left by deleting your own row', async () => {
    await makeAdmin();
    await assertFails(deleteDoc(doc(asAdmin(), 'admins', ADMIN)));
  });
});

describe('everything else', () => {
  it('is denied by default', async () => {
    await assertFails(getDoc(doc(as(VI), 'app_counters', 'devices')));
    await assertFails(setDoc(doc(as(VI), 'anything', 'at-all'), { x: 1 }));
  });
});

describe('saved places — home, work, school', () => {
  it('the owner reads and writes their own', async () => {
    const db = as(VI);
    await assertSucceeds(
      setDoc(doc(db, 'users', VI, 'saved_places', 'home'), {
        label: 'Home',
        lat: 14.79,
        lng: 120.92,
        kind: 'home',
      }),
    );
    await assertSucceeds(getDoc(doc(db, 'users', VI, 'saved_places', 'home')));
    await assertSucceeds(deleteDoc(doc(db, 'users', VI, 'saved_places', 'home')));
  });

  it('a paired guardian is not given them, consent or not', async () => {
    // Where someone *is* is granted by location consent. Where they *go*
    // is a different thing to know about a person, and nobody asked for it.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', VI, 'saved_places', 'home'), {
        label: 'Home',
        lat: 14.79,
        lng: 120.92,
        kind: 'home',
      });
      await updateDoc(doc(ctx.firestore(), 'users', VI), {
        'consent.location': true,
      });
    });
    await assertFails(
      getDoc(doc(as(GUARDIAN), 'users', VI, 'saved_places', 'home')),
    );
  });

  it('nobody else can write one against your account', async () => {
    await assertFails(
      setDoc(doc(as(STRANGER), 'users', VI, 'saved_places', 'home'), {
        label: 'Home',
        lat: 0,
        lng: 0,
        kind: 'home',
      }),
    );
  });
});

describe('account management from the dashboard', () => {
  const REMOVED = 'removed-1';

  it('an admin can change the details the dashboard edits', async () => {
    await makeAdmin();
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'users', VI), {
        name: 'Bob Reyes',
        displayName: 'Bob Reyes',
        impairment: 'colourBlind',
        age: 41,
        updatedAt: serverTimestamp(),
        updatedBy: ADMIN,
      }),
    );
  });

  it("an admin cannot switch on someone's consent", async () => {
    // Whether someone's location is shared is theirs to decide.
    await makeAdmin();
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', VI), { 'consent.location': true }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', VI), { email: 'other@example.com' }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', VI), { onboardingSteps: [] }),
    );
  });

  it('an admin can change a role, but never to admin', async () => {
    await makeAdmin();
    await assertSucceeds(
      updateDoc(doc(asAdmin(), 'users', VI), { role: 'guardian' }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), 'users', VI), { role: 'admin' }),
    );
  });

  it('owners still edit their own details, and still not their role', async () => {
    await assertSucceeds(
      updateDoc(doc(as(VI), 'users', VI), { displayName: 'Bob' }),
    );
    await assertFails(updateDoc(doc(as(VI), 'users', VI), { role: 'guardian' }));
  });

  describe('removing an account', () => {
    const markRemoved = () =>
      setDoc(doc(asAdmin(), 'removed_accounts', VI), {
        email: 'vi@example.com',
        role: 'vi',
        removedAt: serverTimestamp(),
        removedBy: ADMIN,
      });

    it('only an admin can mark an account removed, as themselves', async () => {
      await assertFails(
        setDoc(doc(as(STRANGER), 'removed_accounts', VI), {
          removedBy: STRANGER,
        }),
      );
      await makeAdmin();
      await assertFails(
        setDoc(doc(asAdmin(), 'removed_accounts', VI), { removedBy: STRANGER }),
      );
      await assertSucceeds(markRemoved());
    });

    it('an administrator cannot be removed from the dashboard', async () => {
      await makeAdmin();
      await assertFails(
        setDoc(doc(asAdmin(), 'removed_accounts', ADMIN), { removedBy: ADMIN }),
      );
    });

    it('the removed account can see that it was removed; nobody else can', async () => {
      await makeAdmin();
      await markRemoved();
      await assertSucceeds(getDoc(doc(as(VI), 'removed_accounts', VI)));
      await assertFails(getDoc(doc(as(STRANGER), 'removed_accounts', VI)));
      await assertFails(
        updateDoc(doc(asAdmin(), 'removed_accounts', VI), { role: 'guardian' }),
      );
    });

    it('a removed account cannot write its profile or make a new one', async () => {
      await makeAdmin();
      await markRemoved();
      await assertFails(
        updateDoc(doc(as(VI), 'users', VI), { displayName: 'Still here' }),
      );
      await env.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), 'users', VI));
      });
      await assertFails(
        setDoc(doc(as(VI), 'users', VI), { uid: VI, role: 'vi' }),
      );
    });

    it('a removed account cannot hand out codes or link a guardian', async () => {
      await makeAdmin();
      await markRemoved();
      await assertFails(
        setDoc(doc(as(VI), 'pairing_codes', 'FH29MR47'), {
          ownerId: VI,
          usedBy: null,
          expiresAt: hoursFromNow(1),
        }),
      );
    });

    it('a removed account can still delete its saved places, not add them', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'users', VI, 'saved_places', 'home'), {
          label: 'Home',
          lat: 14.79,
          lng: 120.92,
          kind: 'home',
        });
      });
      await makeAdmin();
      await markRemoved();
      await assertFails(
        setDoc(doc(as(VI), 'users', VI, 'saved_places', 'work'), {
          label: 'Work',
        }),
      );
      await assertSucceeds(
        deleteDoc(doc(as(VI), 'users', VI, 'saved_places', 'home')),
      );
    });

    it("an admin can delete the account's codes and links", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'pairing_codes', 'FH29MR47'), {
          ownerId: VI,
          usedBy: null,
          expiresAt: hoursFromNow(1),
        });
      });
      await makeAdmin();
      await assertSucceeds(deleteDoc(doc(asAdmin(), 'pairing_codes', 'FH29MR47')));
      await assertSucceeds(
        deleteDoc(doc(asAdmin(), 'pairings', pairingId(GUARDIAN, VI))),
      );
      await assertSucceeds(deleteDoc(doc(asAdmin(), 'users', VI)));
    });

    it('an account that was never removed is unaffected', async () => {
      await assertSucceeds(
        setDoc(doc(as(REMOVED), 'users', REMOVED), { uid: REMOVED, role: 'vi' }),
      );
    });
  });
});

describe('navigation history', () => {
  const trip = (db, id = 'trip-1') =>
    doc(db, 'navigation_history', VI, 'entries', id);

  const daysFromNow = (days) => new Date(Date.now() + days * 24 * 3600_000);

  const entry = (overrides = {}) => ({
    destinationName: 'Home',
    destinationAddress: 'Rizal Street, Malolos',
    destinationLat: 14.8,
    destinationLng: 120.9,
    originLat: 14.79,
    originLng: 120.92,
    startedAt: serverTimestamp(),
    endedAt: null,
    status: 'ongoing',
    expiresAt: daysFromNow(30),
    ...overrides,
  });

  it('the user can open a trip and read it back', async () => {
    const db = as(VI);
    await assertSucceeds(setDoc(trip(db), entry()));
    await assertSucceeds(getDoc(trip(db)));
  });

  it('a paired guardian can read it without location consent', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(trip(ctx.firestore()), entry({
        startedAt: new Date(),
        expiresAt: daysFromNow(30),
      }));
    });
    await assertSucceeds(getDoc(trip(as(GUARDIAN))));
    await assertSucceeds(
      getDocs(query(
        collection(as(GUARDIAN), 'navigation_history', VI, 'entries'),
        orderBy('startedAt', 'desc'),
      )),
    );
  });

  it('a stranger, and an admin, cannot read it', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(trip(ctx.firestore()), entry({ startedAt: new Date() }));
    });
    await assertFails(getDoc(trip(as(STRANGER))));
    await makeAdmin();
    await assertFails(getDoc(trip(asAdmin())));
  });

  it('nobody else can open a trip, and it has to be ongoing', async () => {
    await assertFails(setDoc(trip(as(GUARDIAN)), entry()));
    await assertFails(setDoc(trip(as(STRANGER)), entry()));
    await assertFails(setDoc(trip(as(VI)), entry({ status: 'completed' })));
    await assertFails(setDoc(trip(as(VI)), entry({ expiresAt: daysFromNow(10) })));
  });

  it('the user can mark their own trip completed or cancelled, and nothing else', async () => {
    const db = as(VI);
    await assertSucceeds(setDoc(trip(db), entry()));
    await assertSucceeds(updateDoc(trip(db), {
      status: 'completed',
      endedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(trip(db), { status: 'cancelled' }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(trip(ctx.firestore(), 'trip-2'), entry({ startedAt: new Date() }));
    });
    await assertSucceeds(updateDoc(trip(db, 'trip-2'), {
      status: 'cancelled',
      endedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(trip(db, 'trip-2'), { destinationLat: 0 }));
    await assertFails(updateDoc(trip(as(GUARDIAN), 'trip-2'), {
      status: 'completed',
      endedAt: serverTimestamp(),
    }));
  });

  it('the user can delete their own trips, and a guardian cannot', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(trip(ctx.firestore()), entry({ startedAt: new Date() }));
    });
    await assertFails(deleteDoc(trip(as(GUARDIAN))));
    await assertSucceeds(deleteDoc(trip(as(VI))));
  });
});

describe('obstacle history', () => {
  const event = (db, id = 'obs-1') =>
    doc(db, 'users', VI, 'obstacle_events', id);

  const row = () => ({
    type: 'car',
    lat: 14.84,
    lng: 120.81,
    distanceMetres: 1.5,
    distanceApproximate: true,
    at: new Date(),
  });

  const allowActivity = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', VI), {
        consent: {
          location: false,
          history: false,
          recording: false,
          faces: false,
          activity: true,
        },
      }, { merge: true });
    });

  it('the user cannot write one without activity consent', async () => {
    await assertFails(setDoc(event(as(VI)), row()));
  });

  it('the user writes and reads their own, and a paired guardian reads only with consent', async () => {
    await allowActivity();
    const db = as(VI);
    await assertSucceeds(setDoc(event(db), row()));
    await assertSucceeds(getDoc(event(db)));
    await assertSucceeds(
      getDocs(query(
        collection(as(GUARDIAN), 'users', VI, 'obstacle_events'),
        orderBy('at', 'desc'),
      )),
    );
  });

  it('a paired guardian cannot read it when activity consent is off', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(event(ctx.firestore()), row());
    });
    await assertFails(getDoc(event(as(GUARDIAN))));
  });

  it('a guardian cannot write, a stranger cannot read, and nobody can edit', async () => {
    await allowActivity();
    await assertFails(setDoc(event(as(GUARDIAN)), row()));
    await assertSucceeds(setDoc(event(as(VI)), row()));
    await assertFails(getDoc(event(as(STRANGER))));
    await assertFails(updateDoc(event(as(VI)), { type: 'bus' }));
    await assertFails(deleteDoc(event(as(GUARDIAN))));
    await assertSucceeds(deleteDoc(event(as(VI))));
  });
});

describe('guardian alerts', () => {
  const alert = (db, id = 'alert-1') =>
    doc(db, 'users', VI, 'guardian_alerts', id);

  const row = () => ({
    kind: 'route_deviation',
    message: 'Left the planned route.',
    at: new Date(),
    lat: 14.84,
    lng: 120.81,
  });

  const allowLocation = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', VI), {
        consent: {
          location: true,
          history: false,
          recording: false,
          faces: false,
        },
      }, { merge: true });
    });

  it('the user cannot write one without location consent', async () => {
    await assertFails(setDoc(alert(as(VI)), row()));
  });

  it('the user writes one, and only a paired guardian can read it', async () => {
    await allowLocation();
    await assertSucceeds(setDoc(alert(as(VI)), row()));
    await assertFails(getDoc(alert(as(VI))));
    await assertSucceeds(getDoc(alert(as(GUARDIAN))));
    await assertSucceeds(
      getDocs(query(
        collection(as(GUARDIAN), 'users', VI, 'guardian_alerts'),
        orderBy('at', 'desc'),
      )),
    );
  });

  it('a paired guardian cannot read it when location consent is off', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(alert(ctx.firestore()), row());
    });
    await assertFails(getDoc(alert(as(GUARDIAN))));
  });

  it('a guardian cannot write, a stranger cannot read, and nobody can edit', async () => {
    await allowLocation();
    await assertFails(setDoc(alert(as(GUARDIAN)), row()));
    await assertFails(setDoc(alert(as(STRANGER)), row()));
    await assertSucceeds(setDoc(alert(as(VI)), row()));
    await assertFails(getDoc(alert(as(STRANGER))));
    await assertFails(updateDoc(alert(as(VI)), { message: 'changed' }));
    await assertFails(deleteDoc(alert(as(VI))));
    await assertFails(deleteDoc(alert(as(GUARDIAN))));
  });

  it('an admin cannot read it', async () => {
    await allowLocation();
    await assertSucceeds(setDoc(alert(as(VI)), row()));
    await makeAdmin();
    await assertFails(getDoc(alert(asAdmin())));
  });
});

describe('event clips', () => {
  const clip = (db, id = 'clip-1') => doc(db, 'event_clips', id);
  const frame = (db, id = 'clip-1', frameId = '0') =>
    doc(db, 'event_clips', id, 'frames', frameId);

  const row = (userId = VI) => ({
    userId,
    triggers: ['obstacle'],
    at: new Date(),
    endedAt: new Date(),
    frameCount: 1,
    hasFrames: true,
    expiresAt: hoursFromNow(24 * 7),
    lat: 14.6,
    lng: 120.98,
  });

  const picture = (userId = VI) => ({
    userId,
    i: 0,
    at: new Date(),
    jpeg: Bytes.fromUint8Array(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])),
    w: 160,
    h: 120,
  });

  const allowRecording = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', VI), {
        consent: {
          location: false,
          history: false,
          recording: true,
          faces: false,
        },
      }, { merge: true });
    });

  it('the owner with recording consent can create a clip and its frames', async () => {
    await allowRecording();
    await assertSucceeds(setDoc(clip(as(VI)), row()));
    await assertSucceeds(setDoc(frame(as(VI)), picture()));
  });

  it('recording consent off cannot create', async () => {
    await assertFails(setDoc(clip(as(VI)), row()));
    await assertFails(setDoc(frame(as(VI)), picture()));
  });

  it('a removed account cannot create', async () => {
    await allowRecording();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'removed_accounts', VI), {
        removedBy: ADMIN,
      });
    });
    await assertFails(setDoc(clip(as(VI)), row()));
  });

  it('the owner can list and delete their own, and cannot edit', async () => {
    await allowRecording();
    await assertSucceeds(setDoc(clip(as(VI)), row()));
    await assertSucceeds(setDoc(frame(as(VI)), picture()));
    await assertSucceeds(
      getDocs(query(collection(as(VI), 'event_clips'), orderBy('at', 'desc'))),
    );
    await assertSucceeds(getDoc(frame(as(VI))));
    await assertFails(updateDoc(clip(as(VI)), { triggers: ['sos'] }));
    await assertFails(updateDoc(frame(as(VI)), { i: 1 }));
    await assertSucceeds(deleteDoc(frame(as(VI))));
    await assertSucceeds(deleteDoc(clip(as(VI))));
  });

  it('a guardian cannot read or delete, and a stranger cannot read', async () => {
    await allowRecording();
    await assertSucceeds(setDoc(clip(as(VI)), row()));
    await assertSucceeds(setDoc(frame(as(VI)), picture()));
    await assertFails(getDoc(clip(as(GUARDIAN))));
    await assertFails(getDoc(frame(as(GUARDIAN))));
    await assertFails(deleteDoc(clip(as(GUARDIAN))));
    await assertFails(getDoc(clip(as(STRANGER))));
    await assertFails(setDoc(clip(as(STRANGER)), row(STRANGER)));
  });

  it('an admin can read and cannot delete or write', async () => {
    await allowRecording();
    await assertSucceeds(setDoc(clip(as(VI)), row()));
    await assertSucceeds(setDoc(frame(as(VI)), picture()));
    await makeAdmin();
    await assertSucceeds(getDoc(clip(asAdmin())));
    await assertSucceeds(getDoc(frame(asAdmin())));
    await assertSucceeds(
      getDocs(query(collection(asAdmin(), 'event_clips'), orderBy('at', 'desc'))),
    );
    await assertFails(deleteDoc(clip(asAdmin())));
    await assertFails(setDoc(clip(asAdmin()), row(ADMIN)));
  });

  it('a frame without the owner id is refused', async () => {
    await allowRecording();
    await assertFails(setDoc(frame(as(VI)), picture(GUARDIAN)));
  });
});
