import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/alerts/reachability.dart';

/// Registers this device for §3.2 guardian alerts and keeps the token current.
class PushService {
  PushService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  /// Android channel id. Declared in AndroidManifest.xml as the default for
  /// FCM notifications so they arrive at high importance - heads-up and
  /// audible - rather than silently in the shade.
  static const String emergencyChannelId = 'impairgency_emergency';

  Future<AlertReachability> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      // Asked for, rarely granted. Apple gates it behind an entitlement; the
      // app degrades to [AlertReachability.normal] and says what that means.
      criticalAlert: true,
    );
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional =>
        settings.criticalAlert == AppleNotificationSetting.enabled
            ? AlertReachability.critical
            : AlertReachability.normal,
      _ => AlertReachability.denied,
    };
  }

  /// Stores this device's token under the signed-in account and follows
  /// refreshes.
  ///
  /// Tokens rotate - on reinstall, on restore, and occasionally on their own.
  /// A guardian whose token went stale is a guardian who is silently no longer
  /// reachable, which is the failure mode this exists to prevent.
  Future<void> register(String uid) async {
    final token = await _messaging.getToken();
    if (token != null) await _store(uid, token);
    _messaging.onTokenRefresh.listen((t) => _store(uid, t));
  }

  Future<void> _store(String uid, String token) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('push_tokens')
        .doc(token)
        .set({
      'token': token,
      'platform': kIsWeb
          ? 'web'
          : Platform.isIOS
              ? 'ios'
              : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes this device on sign-out, so alerts for one guardian do not keep
  /// arriving on a phone somebody else is now using.
  Future<void> unregister(String uid) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('push_tokens')
        .doc(token)
        .delete();
  }
}
