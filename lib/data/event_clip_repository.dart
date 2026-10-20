/// Event clips in Firestore: one small document, then one document per frame.
///
/// A frame is its own document so a clip cannot hit the 1 MiB limit. The
/// frame carries [userId] too, because a rule that reads the parent does not
/// see the parent write in the same batch.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/clips/event_clip.dart';
import '../core/clips/gray_jpeg.dart';

/// Where a finished clip is written. Tests pass a fake. The app uses
/// [EventClipRepository].
abstract class EventClipSink {
  Future<void> save(String uid, ClosedClip clip);
}

class EventClipRepository implements EventClipSink {
  EventClipRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _clips =>
      _db.collection('event_clips');

  @override
  Future<void> save(String uid, ClosedClip clip) async {
    final jpegs = clip.frames.isEmpty
        ? const <Uint8List>[]
        : await compute(encodeClipJpegs, clip.frames);
    final ref = _clips.doc();
    final at = Timestamp.fromDate(clip.at);
    final batch = _db.batch();
    batch.set(ref, {
      'userId': uid,
      'triggers': clip.triggers,
      'at': at,
      'endedAt': Timestamp.fromDate(clip.endedAt),
      if (clip.latitude != null) 'lat': clip.latitude,
      if (clip.longitude != null) 'lng': clip.longitude,
      'frameCount': jpegs.length,
      'hasFrames': jpegs.isNotEmpty,
      'expiresAt': Timestamp.fromDate(clip.at.add(kClipRetention)),
    });
    for (var i = 0; i < jpegs.length; i++) {
      final frame = clip.frames[i];
      batch.set(ref.collection('frames').doc('$i'), {
        'userId': uid,
        'i': i,
        'at': Timestamp.fromDate(frame.at),
        'jpeg': Blob(jpegs[i]),
        'w': frame.width,
        'h': frame.height,
      });
    }
    await batch.commit();
  }

  /// Newest first, from the last [kClipRetention]. The page filters user,
  /// day, and trigger itself, so this query is a single field.
  Future<List<EventClipRecord>> recent({DateTime? now, int limit = 250}) async {
    final since = (now ?? DateTime.now()).subtract(kClipRetention);
    final snap = await _clips
        .where('at', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('at', descending: true)
        .limit(limit)
        .get();
    return [for (final doc in snap.docs) _record(doc)];
  }

  Future<List<StoredClipFrame>> frames(String clipId) async {
    final snap = await _clips.doc(clipId).collection('frames').orderBy('i').get();
    final frames = <StoredClipFrame>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final jpeg = data['jpeg'];
      if (jpeg is! Blob) continue;
      frames.add(StoredClipFrame(
        index: data['i'] is int ? data['i'] as int : frames.length,
        jpeg: jpeg.bytes,
        width: data['w'] is int ? data['w'] as int : kClipWidth,
        height: data['h'] is int ? data['h'] as int : kClipHeight,
      ));
    }
    return frames;
  }

  /// Deletes this user's clips older than [kClipRetention], a few at a time.
  ///
  /// The phone does this once per sign-in. A failure leaves the old rows;
  /// it does not throw, and it does not block sign-in. Needs the
  /// `event_clips` index on userId + at.
  Future<int> deleteExpired(String uid, {DateTime? now}) async {
    try {
      final cutoff = (now ?? DateTime.now()).subtract(kClipRetention);
      var removed = 0;
      for (var n = 0; n < 40; n++) {
        final page = await _clips
            .where('userId', isEqualTo: uid)
            .where('at', isLessThan: Timestamp.fromDate(cutoff))
            .orderBy('at')
            .limit(1)
            .get();
        if (page.docs.isEmpty) break;
        final doc = page.docs.first;
        while (true) {
          final frames =
              await doc.reference.collection('frames').limit(400).get();
          if (frames.docs.isEmpty) break;
          final batch = _db.batch();
          for (final frame in frames.docs) {
            batch.delete(frame.reference);
          }
          await batch.commit();
          if (frames.docs.length < 400) break;
        }
        await doc.reference.delete();
        removed++;
      }
      return removed;
    } catch (e) {
      debugPrint('event clip cleanup failed: $e');
      return 0;
    }
  }

  EventClipRecord _record(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final at = data['at'];
    final ended = data['endedAt'];
    final triggers = data['triggers'];
    return EventClipRecord(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      triggers: [
        for (final trigger in triggers is List ? triggers : const [])
          if (trigger is String) trigger,
      ],
      at: at is Timestamp ? at.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: ended is Timestamp
          ? ended.toDate()
          : at is Timestamp
              ? at.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0),
      latitude: data['lat'] is num ? (data['lat'] as num).toDouble() : null,
      longitude: data['lng'] is num ? (data['lng'] as num).toDouble() : null,
      frameCount: data['frameCount'] is int ? data['frameCount'] as int : 0,
      hasFrames: data['hasFrames'] == true,
    );
  }
}
