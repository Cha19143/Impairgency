/// How reachable a guardian actually is, and what to tell them about it.
///
/// Pure, and outside `data/`, so the wording a guardian relies on in an
/// emergency can be tested without Firebase.
library;

/// How reliably this device can be reached in an emergency.
///
/// §7 asks emergency features to have fallbacks "when possible". A fallback is
/// only possible if the app knows it is needed, which is what this reports.
enum AlertReachability {
  /// Notifications allowed. On iOS this still means Do Not Disturb can hold an
  /// alert back - see [criticalAlertsUnavailableGuidance].
  normal,

  /// iOS critical alerts granted: the alert sounds through silent and Do Not
  /// Disturb. Requires an Apple entitlement most projects will not have.
  critical,

  /// Notifications refused. A guardian who has refused them is a guardian who
  /// will not be told, and the app has to say so rather than imply otherwise.
  denied,
}

/// What to tell a guardian about how they will and will not be reached.
///
/// The requirements document asks for alerts that "prioritize emergency
/// delivery, including appropriate vibration or alert behavior where supported
/// by the device and operating system". The last clause is doing real work:
/// on iOS, without a critical-alert entitlement, Do Not Disturb will hold an
/// emergency notification. Saying so is the fallback.
String criticalAlertsUnavailableGuidance(AlertReachability reachability) =>
    switch (reachability) {
      AlertReachability.critical =>
        'Emergency alerts will sound even if your phone is silent or on Do Not '
            'Disturb.',
      AlertReachability.normal =>
        'Emergency alerts will vibrate and make a sound. They will not come '
            'through while your phone is on Do Not Disturb, so add ImpairGency '
            'to your allowed apps in your phone settings.',
      AlertReachability.denied =>
        'Notifications are turned off, so you will not be told when an '
            'emergency happens. Turn them on in Settings.',
    };
