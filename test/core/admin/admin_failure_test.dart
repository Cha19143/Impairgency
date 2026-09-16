import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/admin/admin_user.dart';

FirebaseException firestore(String code) => FirebaseException(
    plugin: 'cloud_firestore', code: code, message: 'as Firestore says it');

void main() {
  // The real exception type, not a string made to look like one: the sorting
  // reads the code out of what it prints, so a change to that format has to
  // fail here rather than on the live dashboard.
  group('a failed dashboard read is described by its cause', () {
    test('a refusal from the rules', () {
      expect(describeFailure(firestore('permission-denied')),
          AdminLoadFailure.refused);
    });

    test('no connection, or no answer in time', () {
      // What a read says when the browser is offline.
      expect(describeFailure(firestore('unavailable')),
          AdminLoadFailure.unreachable);
      expect(describeFailure(TimeoutException('no answer')),
          AdminLoadFailure.unreachable);
    });

    test('anything else is blamed on neither', () {
      // A query without its index is a bug to fix, not a roster to join.
      expect(describeFailure(firestore('failed-precondition')),
          AdminLoadFailure.other);
      expect(describeFailure(StateError('a bug')), AdminLoadFailure.other);
    });
  });
}
