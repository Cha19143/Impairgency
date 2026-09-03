/**
 * Server-side work that must not run on a client.
 *
 * The SOS fan-out is here rather than in the app for a reason that matters: a
 * phone in an emergency may be dropped, out of battery, or out of signal a
 * second after the SOS is written. Once the document lands, delivery is the
 * server's problem and no longer depends on the phone staying alive.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

initializeApp();

const db = getFirestore();

/** Android channel declared in AndroidManifest.xml. */
const EMERGENCY_CHANNEL = 'impairgency_emergency';

/**
 * §3.2 — when a visually impaired user activates SOS, their guardians are
 * alerted immediately, with the latest location available and a way to call.
 */
export const onSosCreated = onDocumentCreated(
  'sos_events/{eventId}',
  async (event) => {
    const sos = event.data?.data();
    if (!sos?.userId) {
      logger.warn('SOS document with no userId', { id: event.params.eventId });
      return;
    }

    const [user, pairings] = await Promise.all([
      db.doc(`users/${sos.userId}`).get(),
      db.collection('pairings').where('viUserId', '==', sos.userId).get(),
    ]);

    if (pairings.empty) {
      // Recorded on the event so the receipt the user hears can say nobody was
      // reached, rather than implying success. An SOS with no guardian is the
      // case the app must be honest about.
      await event.data.ref.update({
        'legs.guardianPush': { status: 'no_guardians', at: new Date() },
      });
      return;
    }

    const guardianIds = pairings.docs.map((d) => d.data().guardianId);
    const tokenDocs = await Promise.all(
      guardianIds.map((id) =>
        db.collection(`users/${id}/push_tokens`).get(),
      ),
    );
    const tokens = tokenDocs.flatMap((snap) =>
      snap.docs.map((d) => d.id),
    );

    if (tokens.length === 0) {
      await event.data.ref.update({
        'legs.guardianPush': { status: 'no_devices', at: new Date() },
      });
      return;
    }

    const name = user.data()?.displayName ?? 'Someone you watch over';
    const place = sos.location
      ? `Last location shared ${sos.location.trust === 'fresh' ? 'just now' : 'earlier'}.`
      : 'No location was available.';

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `${name} needs help`,
        body: place,
      },
      data: {
        type: 'sos',
        eventId: event.params.eventId,
        userId: sos.userId,
      },
      android: {
        // High priority wakes a dozing device; the channel carries the sound
        // and heads-up behaviour. Both are needed - priority alone lands
        // silently on a default-importance channel.
        priority: 'high',
        notification: {
          channelId: EMERGENCY_CHANNEL,
          priority: 'max',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            sound: 'default',
            // interruptionLevel 'critical' requires an Apple entitlement most
            // projects do not have. 'time-sensitive' is the honest fallback:
            // it breaks through Focus, though not Do Not Disturb.
            'interruption-level': 'time-sensitive',
          },
        },
      },
    });

    // Per-token outcomes, so the user's receipt can say which guardians were
    // actually reached instead of claiming all of them were.
    await event.data.ref.update({
      'legs.guardianPush': {
        status: response.failureCount === 0 ? 'delivered' : 'partial',
        sent: response.successCount,
        failed: response.failureCount,
        guardians: guardianIds.length,
        at: new Date(),
      },
    });

    // A token that FCM rejects is a device that no longer exists. Leaving it
    // makes every future SOS slower and the success count a lie.
    const stale = [];
    response.responses.forEach((r, i) => {
      const code = r.error?.code ?? '';
      if (
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-argument')
      ) {
        stale.push(tokens[i]);
      }
    });
    if (stale.length) {
      logger.info(`Pruning ${stale.length} dead token(s)`);
      await Promise.all(
        guardianIds.map((id) =>
          Promise.all(
            stale.map((t) =>
              db.doc(`users/${id}/push_tokens/${t}`).delete().catch(() => {}),
            ),
          ),
        ),
      );
    }
  },
);
