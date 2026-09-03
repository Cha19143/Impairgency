import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/alerts/alert_presenter.dart';
import '../core/alerts/sos_alert.dart';

/// Raises the emergency alert on this device.
///
/// The channel id matches the one declared in AndroidManifest.xml as FCM's
/// default, so a locally raised alert and a server-pushed one look and sound
/// identical. When Cloud Functions become affordable, nothing the guardian sees
/// has to change.
class LocalAlertPresenter implements AlertPresenter {
  LocalAlertPresenter({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const String channelId = 'impairgency_emergency';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    channelId,
    'Emergency alerts',
    description:
        'Sounds when someone you watch over calls for help. Do not turn this '
        'off.',
    // The whole point. Default importance means no sound and no heads-up,
    // which is indistinguishable from the feature not working.
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  @override
  Future<void> prepare() async {
    if (_ready) return;

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestSoundPermission: true,
          requestBadgePermission: false,
        ),
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Android 13+ requires this at runtime. A guardian who never granted it is
    // a guardian who will never be told, so it is asked for at start-up rather
    // than at the moment of an emergency.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  @override
  Future<void> show(SosAlert alert) async {
    await prepare();
    await _plugin.show(
      alert.eventId.hashCode,
      alert.title,
      alert.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          // Survives a swipe-away and stays until acted on. An emergency the
          // guardian brushed off their lock screen by accident is an emergency
          // they were never told about.
          ongoing: false,
          autoCancel: true,
          fullScreenIntent: true,
          ticker: alert.title,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: alert.eventId,
    );
  }
}
