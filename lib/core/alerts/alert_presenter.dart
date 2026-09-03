import 'sos_alert.dart';

/// Shows an alert on this device.
///
/// An interface so the guardian watcher can be tested without a notification
/// plugin, and so the delivery mechanism can be swapped - a Cloud Function
/// sending real push is the same shape from the watcher's point of view.
abstract interface class AlertPresenter {
  /// Prepares channels and permissions. Safe to call more than once.
  Future<void> prepare();

  Future<void> show(SosAlert alert);
}

/// Records instead of showing. Used in tests.
class RecordingAlertPresenter implements AlertPresenter {
  final List<SosAlert> shown = [];
  int prepares = 0;

  @override
  Future<void> prepare() async => prepares++;

  @override
  Future<void> show(SosAlert alert) async => shown.add(alert);
}
