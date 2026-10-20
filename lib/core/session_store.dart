/// Persistence for the handful of facts the router needs before anything is
/// signed in.
///
/// An interface rather than `SharedPreferences` directly so the routing tests
/// can run without a platform channel.
library;

import 'contacts/emergency_contact.dart';
import 'navigation/destination.dart';
import 'speech/speech_pace.dart';

/// The handful of facts the app needs before it can reach the network.
class CachedProfile {
  const CachedProfile({
    this.role,
    this.consent = const {},
    this.contacts = const [],
    this.guardianCount = 0,
  });

  /// 'vi' or 'guardian'. Cached so the router knows which app to open
  /// before - or without - the account document being readable, and set
  /// *before* the account is created so the guard never sees a guardian as
  /// a visually impaired user mid-registration.
  final String? role;

  final Map<String, bool> consent;

  /// The emergency contacts, in calling order. See `emergency_contact.dart`
  /// for what the order means.
  final List<EmergencyContact> contacts;

  final int guardianCount;

  /// The first contact, for anything that only wants one.
  String? get contactName => contacts.isEmpty ? null : contacts.first.name;
  String? get contactNumber =>
      contacts.isEmpty ? null : contacts.first.number;

  bool get isGuardian => role == 'guardian';

  CachedProfile copyWith({
    String? role,
    Map<String, bool>? consent,
    List<EmergencyContact>? contacts,
    int? guardianCount,
  }) =>
      CachedProfile(
        role: role ?? this.role,
        consent: consent ?? this.consent,
        contacts: contacts ?? this.contacts,
        guardianCount: guardianCount ?? this.guardianCount,
      );
}

abstract interface class SessionStore {
  Future<bool> safetyAcknowledged();
  Future<void> acknowledgeSafety();

  /// Read on every launch, before anything touches the network.
  ///
  /// §7 asks emergency features to have fallbacks. Account-first onboarding
  /// means an unregistered phone with no signal is a phone with no SOS - but a
  /// phone that has been set up must still reach its dashboard, with the alarm
  /// and the dialler live, when it cannot reach Firestore. That is what this
  /// cache is for.
  Future<CachedProfile> cachedProfile();

  Future<void> cacheProfile(CachedProfile profile);

  /// Saved destinations, so the Home button knows where Home is offline.
  Future<List<Destination>> cachedPlaces();
  Future<void> cachePlaces(List<Destination> places);

  /// Onboarding steps already finished, so setup can resume after a kill.
  Future<Set<String>> completedSteps();
  Future<void> markStepComplete(String route);

  /// Whether voice commands are listened for without a tap, or null if the
  /// user has never chosen. A setting of the phone and of how its owner uses
  /// it, not of an account, so [forgetAccount] leaves it alone.
  Future<bool?> handsFree();
  Future<void> setHandsFree(bool on);

  /// Slow, normal, or fast, or null if the user has never chosen.
  ///
  /// Normal is the engine's existing 0.45. Like hands-free, this belongs to
  /// the phone, so [forgetAccount] leaves it alone.
  Future<SpeechPace?> speechPace();
  Future<void> setSpeechPace(SpeechPace pace);

  /// Returns the device to how it was before anyone signed in.
  ///
  /// Everything this store holds is about a person, and none of it is scoped to
  /// an account: the completed steps and the cached profile belong to whoever
  /// signed in last. Leaving them in place after a sign-out means the next
  /// person to use this phone walks past setup into someone else's emergency
  /// contact and someone else's consent.
  ///
  /// The safety acknowledgement goes with them, and that is the point rather
  /// than an oversight. §7's notice is what a *person* has been told the app
  /// cannot do, not a box this handset has ticked.
  Future<void> forgetAccount();
}

class InMemorySessionStore implements SessionStore {
  InMemorySessionStore({
    bool acknowledged = false,
    Set<String>? steps,
    CachedProfile? profile,
  })  : _acknowledged = acknowledged,
        _steps = {...?steps},
        _profile = profile ?? const CachedProfile();

  bool _acknowledged;
  final Set<String> _steps;
  CachedProfile _profile;
  List<Destination> _places = const [];
  bool? _handsFree;
  SpeechPace? _speechPace;

  @override
  Future<bool?> handsFree() async => _handsFree;

  @override
  Future<void> setHandsFree(bool on) async => _handsFree = on;

  @override
  Future<SpeechPace?> speechPace() async => _speechPace;

  @override
  Future<void> setSpeechPace(SpeechPace pace) async => _speechPace = pace;

  @override
  Future<CachedProfile> cachedProfile() async => _profile;

  @override
  Future<List<Destination>> cachedPlaces() async => [..._places];

  @override
  Future<void> cachePlaces(List<Destination> places) async =>
      _places = [...places];

  @override
  Future<void> cacheProfile(CachedProfile profile) async => _profile = profile;

  @override
  Future<bool> safetyAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledgeSafety() async => _acknowledged = true;

  @override
  Future<Set<String>> completedSteps() async => {..._steps};

  @override
  Future<void> markStepComplete(String route) async => _steps.add(route);

  @override
  Future<void> forgetAccount() async {
    _steps.clear();
    _profile = const CachedProfile();
    _places = const [];
    _acknowledged = false;
  }
}
