// Seeds the Firebase emulators with just enough to drive the admin dashboard.
//
//   node test/e2e/seed.js
//
// Run with the auth and firestore emulators up. No dependencies and no
// credentials: the auth emulator accepts any API key, and both emulators treat
// `Authorization: Bearer owner` as a rules bypass. That bypass is the only way
// to create an admin - `admins` is unwritable from every client on purpose
// (firestore.rules:288-291), which is the property these tests exist to prove.

const PROJECT = 'demo-impairgency';
const AUTH = 'http://127.0.0.1:9099';
const FIRESTORE = 'http://127.0.0.1:8080';
const DB = `${FIRESTORE}/v1/projects/${PROJECT}/databases/(default)/documents`;

const owner = {
  'Authorization': 'Bearer owner',
  'Content-Type': 'application/json',
};

/// The accounts every test signs in as.
///
/// The uids are chosen rather than generated, so a spec can assert on the exact
/// `admins/<uid>` line the dashboard prints without threading ids through the
/// test run.
export const ADMIN = {
  uid: 'e2e-admin',
  email: 'admin@impairgency.test',
  password: 'dashboard-test-pw',
};

/// A real account deliberately left off the roster. The dashboard should refuse
/// it by name, rather than by showing the sign-in form again.
export const NOT_ADMIN = {
  uid: 'e2e-stranger',
  email: 'nobody@impairgency.test',
  password: 'dashboard-test-pw',
};

/// What the seeded sessions below add up to, so specs assert against one source
/// of truth instead of restating literals. Each number reaches the screen by a
/// different route - a distinct count, a sum, and a median - so no single bug
/// can make them all pass by accident.
export const EXPECTED = {
  activeUsers: 2, // vi-anna and vi-ben
  sessions: 3,
  sosIncidents: 1, // one sosFired, in session three
  positioningQuality: 80, // median discarded fraction is 0.2 -> 80% usable
};

async function ok(response, what) {
  if (!response.ok) {
    throw new Error(`${what} failed: ${response.status} ${await response.text()}`);
  }
  return response;
}

/// Firestore's REST API wants every value tagged with its type.
const str = (v) => ({ stringValue: v });
const int = (v) => ({ integerValue: String(v) });
const dbl = (v) => ({ doubleValue: v });
const time = (d) => ({ timestampValue: d.toISOString() });
const list = (vs) => ({ arrayValue: { values: vs } });
const map = (o) => ({ mapValue: { fields: o } });

async function put(path, fields) {
  await ok(
    await fetch(`${DB}/${path}`, {
      method: 'PATCH',
      headers: owner,
      body: JSON.stringify({ fields }),
    }),
    `write ${path}`,
  );
}

async function createUser({ uid, email, password }) {
  await ok(
    await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts`, {
      method: 'POST',
      headers: owner,
      body: JSON.stringify({ localId: uid, email, password, emailVerified: true }),
    }),
    `create ${email}`,
  );
}

/// Whether the auth emulator holds an account for [email].
export async function authAccountExists(email) {
  const response = await ok(
    await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:query`, {
      method: 'POST',
      headers: owner,
      body: JSON.stringify({}),
    }),
    'list accounts',
  );
  const { userInfo = [] } = await response.json();
  return userInfo.some((user) => user.email === email);
}

/// A Firestore document, read past the rules, or null.
export async function readDoc(path) {
  const response = await fetch(`${DB}/${path}`, { headers: owner });
  if (response.status === 404) return null;
  await ok(response, `read ${path}`);
  return response.json();
}

/// Wipes both emulators so a run never inherits the last one's state.
async function reset() {
  await ok(
    await fetch(`${AUTH}/emulator/v1/projects/${PROJECT}/accounts`, { method: 'DELETE' }),
    'clear auth',
  );
  await ok(
    await fetch(`${FIRESTORE}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
      { method: 'DELETE' }),
    'clear firestore',
  );
}

/// `startedAt` has to land inside the dashboard's 30-day window, or the overview
/// renders its empty state instead of the numbers.
const daysAgo = (n) => new Date(Date.now() - n * 24 * 60 * 60 * 1000);

/// Removes every session summary, leaving the accounts alone. Lets a spec prove
/// the empty state without tearing down the sign-in it just did.
export async function clearSessions() {
  const response = await ok(
    await fetch(`${DB}/session_summaries?pageSize=300`, { headers: owner }),
    'list sessions',
  );
  const { documents = [] } = await response.json();
  for (const doc of documents) {
    await ok(
      await fetch(`${FIRESTORE}/v1/${doc.name}`, { method: 'DELETE', headers: owner }),
      `delete ${doc.name}`,
    );
  }
  return documents.length;
}

export async function seedSessions() {
  // Three sessions across two users, one of them an emergency.
  await put('session_summaries/session-one', {
    sessionId: str('session-one'),
    userId: str('vi-anna'),
    startedAt: time(daysAgo(1)),
    minutes: int(14),
    metres: int(820),
    eventCounts: map({ obstacleDetected: int(6), guidanceGiven: int(4) }),
    discardedFraction: dbl(0.1),
    concernCount: int(0),
    placeLabels: list([str('Home'), str('Corner shop')]),
  });
  await put('session_summaries/session-two', {
    sessionId: str('session-two'),
    userId: str('vi-ben'),
    startedAt: time(daysAgo(3)),
    minutes: int(22),
    metres: int(1500),
    eventCounts: map({ obstacleDetected: int(3), stairsDetected: int(2), textRead: int(1) }),
    discardedFraction: dbl(0.2),
    concernCount: int(1),
    placeLabels: list([str('Home')]),
  });
  await put('session_summaries/session-three', {
    sessionId: str('session-three'),
    userId: str('vi-anna'),
    startedAt: time(daysAgo(6)),
    minutes: int(8),
    metres: int(300),
    eventCounts: map({ sosArmed: int(1), sosFired: int(1), guidanceGiven: int(2) }),
    discardedFraction: dbl(0.3),
    concernCount: int(3),
    placeLabels: list([str('Home')]),
  });
}

export async function seed() {
  await reset();

  await createUser(ADMIN);
  await createUser(NOT_ADMIN);

  // The roster. Existence is the whole check; no field is read
  // (admin_repository.dart:63-69).
  await put(`admins/${ADMIN.uid}`, { grantedAt: time(new Date()) });

  // The accounts §1.2's user table lists.
  await put(`users/${ADMIN.uid}`, {
    displayName: str('Dex the administrator'),
    email: str(ADMIN.email),
    role: str('admin'),
  });
  await put(`users/${NOT_ADMIN.uid}`, {
    displayName: str('Nobody in particular'),
    email: str(NOT_ADMIN.email),
    role: str('vi'),
  });
  await put('users/vi-anna', {
    uid: str('vi-anna'),
    displayName: str('Anna'),
    email: str('anna@impairgency.test'),
    role: str('vi'),
    deviceId: str('device-anna'),
    impairment: str('blind'),
  });
  await put('users/vi-ben', {
    uid: str('vi-ben'),
    displayName: str('Ben'),
    email: str('ben@impairgency.test'),
    role: str('vi'),
    impairment: str('colourBlind'),
  });
  // A guardian watching Anna, so the Guardians filter has someone to find and
  // the Linked column has something to count.
  await put('users/guardian-gina', {
    uid: str('guardian-gina'),
    displayName: str('Gina'),
    email: str('gina@impairgency.test'),
    role: str('guardian'),
  });
  await put('pairings/guardian-gina_vi-anna', {
    guardianId: str('guardian-gina'),
    viUserId: str('vi-anna'),
  });

  await seedSessions();
}

// `node test/e2e/seed.js` runs it; importing it does not.
if (import.meta.url === `file://${process.argv[1]}`) {
  await seed();
  console.log(`seeded ${ADMIN.email} (admin) and ${NOT_ADMIN.email} (not on the roster)`);
  console.log(`seeded ${EXPECTED.sessions} sessions, ${EXPECTED.activeUsers} users, ${EXPECTED.sosIncidents} SOS`);
}
