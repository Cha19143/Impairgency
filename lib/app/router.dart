import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/alert_presenter.dart';
import '../core/auth/email_verification.dart';
import '../core/contacts/emergency_contact.dart';
import '../core/location/location_fix.dart';
import '../core/location/location_policy.dart';
import '../core/location/location_source.dart';
import '../core/location/where_am_i.dart';
import '../core/navigation/destination.dart';
import '../core/navigation/map_services.dart';
import '../core/navigation/place_search.dart';
import '../core/navigation/route.dart';
import '../core/navigation/route_follower.dart' show kPoorFixMetres;
import '../core/places/journey_recorder.dart';
import '../core/places/session_event.dart';
import '../core/places/place.dart';
import '../core/session_store.dart';
import '../core/speech/speaker.dart';
import '../core/vision/faces.dart';
import '../core/vision/friend_recognition.dart';
import '../core/voice/speech_recognizer.dart';
import '../core/voice/voice_commands.dart';
import '../admin/screens/accessibility_screen.dart';
import '../admin/screens/admin_page.dart';
import '../admin/screens/admin_shell.dart';
import '../admin/screens/admin_sign_in_screen.dart';
import '../admin/screens/invite_dialog.dart';
import '../admin/screens/overview_screen.dart';
import '../admin/screens/system_health_screen.dart';
import '../admin/screens/user_dialogs.dart';
import '../admin/screens/users_screen.dart';
import '../core/places/session_summary.dart';
import '../data/admin_account_creator.dart';
import '../data/admin_repository.dart';
import '../data/auth_service.dart';
import '../data/contact_picker.dart';
import '../data/friend_store.dart';
import '../data/geolocator_location_source.dart';
import '../data/guardian_onboarding.dart';
import '../data/guardian_repository.dart';
import '../data/local_alert_presenter.dart';
import '../data/osm_http.dart';
import '../data/osrm_routing_service.dart';
import '../data/photon_place_search.dart';
import '../data/pairing_repository.dart';
import '../data/saved_places_repository.dart';
import '../data/journey_store.dart';
import '../data/location_history_repository.dart';
import '../data/location_sharer.dart';
import '../data/account_status_repository.dart';
import '../data/activity_repository.dart';
import '../core/guardian/activity.dart';
import '../core/guardian/watched_user.dart';
import '../guardian/screens/live_location_screen.dart';
import '../data/sos_engine.dart';
import '../data/stt_speech_recognizer.dart';
import '../guardian/screens/accept_invitation_screen.dart';
import '../guardian/screens/guardian_home_page.dart';
import '../guardian/screens/guardian_register_screen.dart';
import '../shared/widgets/pending_screen.dart';
import '../vi/onboarding/all_set_screen.dart';
import '../vi/onboarding/choose_role_screen.dart';
import '../vi/onboarding/forgot_password_screen.dart';
import '../vi/onboarding/profile_screen.dart';
import '../vi/onboarding/consent_screen.dart';
import '../vi/onboarding/create_account_screen.dart';
import '../vi/onboarding/device_screen.dart';
import '../vi/onboarding/emergency_contact_screen.dart';
import '../vi/onboarding/invite_guardian_screen.dart';
import '../vi/onboarding/onboarding_controller.dart';
import '../vi/onboarding/preferences_screen.dart';
import '../vi/onboarding/sign_in_screen.dart';
import '../vi/onboarding/verify_email_screen.dart';
import '../vi/onboarding/welcome_screen.dart';
import '../vi/screens/consent_centre_screen.dart';
import '../vi/screens/dashboard_screen.dart';
import '../vi/screens/learned_data_screen.dart';
import '../vi/screens/people_screen.dart';
import '../vi/screens/journey_screen.dart';
import '../vi/screens/scan_screen.dart';
import '../vi/screens/settings_screen.dart';
import '../vi/screens/sign_out_screen.dart';
import '../vi/screens/location_debug_screen.dart';
import '../vi/screens/sos_flow.dart';
import '../vi/screens/what_can_i_say_screen.dart';
import '../vi/screens/read_text_screen.dart';
import '../vi/screens/safety_notice_screen.dart';
import '../vi/screens/saved_places_screen.dart';
import '../vi/screens/smart_assistance_screen.dart';
import '../vi/voice_actions.dart';
import '../vi/voice_controller.dart';
import '../vi/widgets/place_search_panel.dart';
import '../vi/widgets/vi_button.dart';
import '../vi/widgets/vi_screen.dart';
import '../vi/widgets/voice_scope_host.dart';
import 'routes.dart';
import 'theme.dart';

/// Live session, fed by FirebaseAuth once `flutterfire configure` has been run
/// against the new project. Until then it reports signed out, which is the
/// correct default: the guard fails closed.
class AppSession extends ChangeNotifier {
  /// Everything past [store] and [speaker] is for tests, which pass fakes;
  /// the app passes nothing and gets the Firebase-backed ones on first use.
  AppSession({
    SessionStore? store,
    Speaker? speaker,
    PairingRepository? pairing,
    SpeechRecognizer? recognizer,
    LocationSharing? sharer,
    ActivityRecorder? activity,
    AuthService? auth,
    OnboardingController? onboarding,
    GuardianOnboarding? guardianOnboarding,
    GuardianRepository? guardian,
    AdminRepository? admin,
    AlertPresenter? alerts,
    AccountStatusRepository? accountStatus,
    RoutingService? routing,
    PlaceSearchService? placeSearch,
    LocationSource? location,
    FriendStore? friendStore,
    JourneyStore? journeyStore,
    bool? dashboard,
  })  : store = store ?? InMemorySessionStore(),
        _dashboard = dashboard ?? kIsWeb,
        speaker = speaker ?? const SilentSpeaker(),
        _pairing = pairing,
        _recognizer = recognizer,
        _sharer = sharer,
        _activity = activity,
        _auth = auth,
        _onboarding = onboarding,
        _guardianOnboarding = guardianOnboarding,
        _guardian = guardian,
        _admin = admin,
        _alerts = alerts,
        _accountStatus = accountStatus,
        _routing = routing,
        _placeSearch = placeSearch,
        _location = location,
        _friendStore = friendStore,
        _journeyStore = journeyStore;

  /// Whether this is the web dashboard: the admin app, and the roster that
  /// guards it. [kIsWeb], unless a test says otherwise.
  bool get dashboard => _dashboard;
  final bool _dashboard;

  /// Where "what the app noticed" goes for the guardian. Null in tests.
  final ActivityRecorder? _activity;
  final _activityThrottle = ActivityThrottle();

  /// Tells the guardian what the app noticed - if the user said it may,
  /// and not the same thing twice in a minute.
  void recordActivity(ActivityKind kind, String detail) {
    final recorder = _activity;
    final uid = _state.uid;
    if (recorder == null || uid == null) return;
    if (_state.consent['activity'] != true) return;
    final headline = ActivityEvent.headline(detail);
    if (headline.isEmpty) return;
    final now = DateTime.now();
    if (!_activityThrottle.admit(kind, headline, now)) return;
    unawaited(recorder
        .record(uid, ActivityEvent(kind: kind, detail: headline, at: now))
        .catchError((_) {}));
  }

  /// Publishes the user's position for their guardians. Null in tests and
  /// nothing then happens; app.dart passes the real one.
  final LocationSharing? _sharer;

  /// Whether the app is on screen. Sharing runs only while it is: the app
  /// does no background work, so a guardian's card should age honestly
  /// rather than show a position the phone stopped reading.
  bool _foreground = true;

  void setForeground(bool foreground) {
    _foreground = foreground;
    _syncSharing(_state);
    _voice?.setForeground(foreground);
    // Away for good, as far as a journey goes, after ten minutes.
    _awayTimer?.cancel();
    _awayTimer = foreground || !(_journeys?.recording ?? false)
        ? null
        : Timer(kJourneyIdleEnd, () => unawaited(journeys.end()));
    // Back from the mail app: if the link was opened, move on without
    // making them find a button.
    if (foreground && _state.needsEmailVerification) {
      unawaited(checkEmailVerified(quietly: true));
    }
  }

  /// Asks Firebase whether the verification link has been opened, and lets
  /// the account through if it has. Returns what the check found.
  ///
  /// [quietly] is the automatic check on returning to the app: it only speaks
  /// when there is good news.
  Future<VerificationCheck> checkEmailVerified({bool quietly = false}) async {
    final result = await auth.checkVerification();
    if (result == VerificationCheck.verified && _state.needsEmailVerification) {
      update(_state.copyWith(needsEmailVerification: false));
      if (quietly) {
        await speaker.speak('Your email address is confirmed.');
      }
    }
    return result;
  }

  /// Keeps the sharer in step with the session: on while a visually impaired
  /// user is signed in, has said "Share where I am", and has the app open;
  /// off otherwise. Switching the consent off also removes the published
  /// point, so the guardian's card says "not sharing" and not somewhere
  /// stale.
  void _syncSharing(SessionState before) {
    final sharer = _sharer;
    if (sharer == null) return;
    final uid = _state.uid;
    final consented = _state.consent['location'] == true;
    if (_state.signedIn && !_state.isGuardian && uid != null && consented) {
      if (_foreground) {
        sharer.start(uid, recordHistory: _state.consent['history'] == true);
      } else {
        sharer.stop();
      }
      return;
    }
    sharer.stop();
    final wasConsented = before.consent['location'] == true;
    if (wasConsented && !consented && uid != null) {
      unawaited(sharer.forget(uid));
    }
  }

  final SessionStore store;
  final Speaker speaker;

  /// [speaker], with priorities. The scan screen needs them; a test that
  /// passed a plain recording speaker gets it back wrapped.
  PrioritySpeaker get prioritySpeaker => withPriorities(speaker);

  SpeechRecognizer? _recognizer;

  /// Where a spoken command sends the user. Set by [createRouter].
  void Function(String route)? navigate;

  VoiceController? _voice;

  /// The microphone, and everything between it and an action.
  ///
  /// One for the whole app rather than one per screen, so the permission is
  /// asked for once, the failure is explained once, and a screen that opens
  /// while another is listening does not end up with two microphones.
  VoiceController get voice => _voice ??= VoiceController(
        recognizer: _recognizer ??= SttSpeechRecognizer(),
        speaker: speaker,
        actions: () => VoiceActions(
          location: const GeolocatorLocationSource(),
          fetchFix: _fixForVoice,
          contactName: _state.contactName,
          hasGuardian: _state.guardianCount > 0,
          goTo: goTo,
          rememberFriend: rememberFriend,
          forgetFriend: forgetFriend,
          setHandsFree: setHandsFree,
        ),
        onNavigate: (route) => navigate?.call(route),
        screenReaderOn: () => WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.accessibleNavigation,
        listeningCue: HapticFeedback.mediumImpact,
      )
        ..handsFree = _handsFree
        ..setForeground(_foreground)
        ..fallbackScope = _dashboard ? null : _listenOn;

  /// What a screen with no voice scope of its own listens for: the everyday
  /// words, hands-free, and its buttons by name - on every screen of the
  /// visually impaired app. Not in the guardian's app, which is used by
  /// someone who can see it and never agreed to an open microphone.
  VoiceScope? _listenOn(String? route) {
    if (route == null || _state.isGuardian) return null;
    if (route.startsWith(Routes.guardianHome) ||
        route.startsWith(Routes.adminRoot) ||
        route == Routes.debug) {
      return null;
    }
    // The first run's safety notice is heard out before the microphone is
    // asked for: the permission prompt would land on top of it.
    if (route == Routes.safety && !_state.safetyAcknowledged) {
      return const VoiceScope(handsFree: false);
    }
    // The SOS flow listens for "cancel" itself. A hands-free window taking
    // the microphone between two of its windows would hear "cancel" as
    // nothing, and the everyday words mean nothing there.
    if (route == Routes.sos) {
      return const VoiceScope(handsFree: false, exclusive: true);
    }
    return const VoiceScope();
  }

  /// Hands-free listening, as the user set it - or, until they have, on for
  /// Android, where it has been tried, and off for iOS until it has been.
  bool _handsFree = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get handsFree => _handsFree;

  Future<void> setHandsFree(bool on) async {
    _handsFree = on;
    _voice?.handsFree = on;
    notifyListeners();
    await store.setHandsFree(on);
  }

  final LocationSource? _location;

  /// Where the phone is. The platform's, unless a test passed its own.
  LocationSource get location =>
      _location ?? const GeolocatorLocationSource();

  OsmHttp? _osm;
  RoutingService? _routing;
  PlaceSearchService? _placeSearch;

  /// Walking routes from OpenStreetMap. None on the web: the dashboard gives
  /// no directions.
  RoutingService? get routing {
    if (_routing != null || kIsWeb) return _routing;
    return _routing = OsrmRoutingService(http: _osm ??= OsmHttp());
  }

  /// Places by name, and street names for "where am I". None on the web.
  PlaceSearchService? get placeSearch {
    if (_placeSearch != null || kIsWeb) return _placeSearch;
    return _placeSearch = PhotonPlaceSearch(http: _osm ??= OsmHttp());
  }

  /// "Take me to…", by voice.
  ///
  /// A saved place answers straight away and opens the journey screen.
  /// Anything else is looked up near the person, and each place found is
  /// offered in turn - "Jollibee, Paseo del Congreso, about 600 metres away.
  /// Say yes to go there, next for another, or no" - because the first match
  /// for a name is often the wrong branch, and going to the wrong one is a
  /// long walk to find out.
  Future<VoiceOutcome> goTo(String query) async {
    final uid = _state.uid;
    final saved =
        uid == null ? await store.cachedPlaces() : await places.list(uid);
    final place = matchSavedPlace(query, saved);
    if (place != null) {
      await setDestination(place);
      return VoiceOutcome(
          spoken: 'Directions to ${place.label}.', route: Routes.journey);
    }
    final search = placeSearch;
    final voice = _voice;
    if (search == null || voice == null) {
      return VoiceOutcome(
        spoken: 'I could not find a saved place called $query. Opening smart '
            'assistance, where places are chosen and saved.',
        route: Routes.assist,
      );
    }

    await speaker.speak('Looking for $query nearby.');
    final result = await searchPlaces(query);
    final problem = result.problem;
    if (problem != null) return VoiceOutcome(spoken: problem);
    final from = result.from;
    final found = result.found;
    if (found.isEmpty) {
      return VoiceOutcome(
          spoken: 'I could not find $query nearby. Saved places still work.');
    }

    for (var i = 0; i < found.length; i++) {
      final candidate = found[i];
      final answer = await voice.ask(candidateQuestion(candidate,
          from: from, more: i < found.length - 1));
      switch (answer?.command) {
        case VoiceCommand.yes:
          final destination = candidate.toDestination();
          await setDestination(destination);
          return VoiceOutcome(
              spoken: 'Directions to ${destination.label}.',
              route: Routes.journey);
        case VoiceCommand.next:
          continue;
        case VoiceCommand.help:
          return const VoiceOutcome(
              spoken: 'Calling for help.', route: Routes.sos);
        default:
          return const VoiceOutcome(spoken: 'Nothing was chosen.');
      }
    }
    return const VoiceOutcome(
        spoken: 'That was the last place I found. Say take me to, and a '
            'place, to look again.');
  }

  FriendStore? _friendStore;

  /// Saved friends' faces, on this phone.
  FriendStore get friendStore => _friendStore ??= FileFriendStore();

  /// Whether the user agreed to "Recognise people I know".
  bool get facesConsented => _state.consent['faces'] == true;

  /// Whose friends: this account's, or the phone's when signed out.
  String get faceOwner => _state.uid ?? 'local';

  String? _pendingFriend;

  /// Someone to meet when the scan screen opens, once.
  String? takePendingFriend() {
    final name = _pendingFriend;
    _pendingFriend = null;
    return name;
  }

  /// Recognition for one visit to the scan screen, or null without consent.
  FriendRecognition? friendRecognition() => !facesConsented
      ? null
      : FriendRecognition(
          store: friendStore,
          owner: faceOwner,
          say: (sentence) => prioritySpeaker.announce(sentence,
              priority: SpeechPriority.info),
        );

  /// "Hello friend Sam", heard away from the scan screen: opens it, where
  /// Sam will be asked and their face taken down.
  Future<VoiceOutcome> rememberFriend(String name) async {
    final friend = normaliseFriendName(name);
    if (friend == null) {
      return const VoiceOutcome(
          spoken: 'Say hello friend, and then their name.');
    }
    if (!facesConsented) return const VoiceOutcome(spoken: kFacesOffPhrase);
    _pendingFriend = friend;
    return VoiceOutcome(
        spoken: 'Opening scan, to meet $friend.', route: Routes.scan);
  }

  /// "Forget Sam", from anywhere: asked, then deleted.
  Future<VoiceOutcome> forgetFriend(String name) async {
    final voice = _voice;
    if (voice == null) return const VoiceOutcome(spoken: 'Nothing was deleted.');
    final recognition = FriendRecognition(
        store: friendStore, owner: faceOwner, say: (_) {});
    await recognition.load();
    return VoiceOutcome(
        spoken: await recognition.forget(name, ask: voice.ask));
  }

  /// Deletes every saved face on this phone for this account; says how many
  /// when there were any. Failure is logged, not thrown: it runs on the way
  /// out of consent and out of the account, which must not get stuck.
  Future<void> _forgetFaces({bool quietly = false}) async {
    try {
      final deleted = await friendStore.deleteAll(faceOwner);
      if (deleted > 0 && !quietly) {
        await speaker.speak(deleted == 1
            ? 'The one saved face on this phone was deleted.'
            : 'The $deleted saved faces on this phone were deleted.');
      }
    } catch (e) {
      debugPrint('Saved faces were not deleted: $e');
    }
  }

  /// Places called [query] near the phone - or, instead, why there are none
  /// to offer: no position, no connection, no search on this device.
  Future<PlaceSearchResult> searchPlaces(String query) async {
    final search = placeSearch;
    if (search == null) {
      return const PlaceSearchResult(
          problem: 'Searching for places is not available here.');
    }
    final source = location;
    final availability = await source.requestPermission();
    if (availability != LocationAvailability.ready) {
      return PlaceSearchResult(
          problem: 'To search nearby I need your location. '
              '${permissionGuidance(availability)}');
    }
    final fix = await bestEffortFix(source, timeout: const Duration(seconds: 6));
    if (fix == null) {
      return const PlaceSearchResult(
          problem: 'I could not get your position, so I cannot search nearby. '
              'Saved places still work.');
    }
    final here = RoutePoint(fix.latitude, fix.longitude);
    try {
      final found = await search.search(query, near: here);
      return PlaceSearchResult(found: nearbyCandidates(found, here), from: here);
    } on MapServiceException catch (e) {
      return PlaceSearchResult(
        problem: switch (e.failure) {
          MapServiceFailure.offline =>
            'Searching for places needs an internet connection. Saved places '
                'still work.',
          MapServiceFailure.busy || MapServiceFailure.timeout =>
            'The place search is busy. Try again in a minute. Saved places '
                'still work.',
          _ => 'The place search is not working right now. Saved places still '
              'work.',
        },
      );
    }
  }

  /// What "where am I" reads back. Not the SOS receipt's sentence, which told
  /// someone who had only asked a question that their location "was sent".
  Future<({LocationAvailability availability, String? summary})>
      _fixForVoice() async {
    final source = location;
    final availability = await source.requestPermission();
    if (availability != LocationAvailability.ready) {
      return (availability: availability, summary: null);
    }
    final fix = await bestEffortFix(source);
    if (fix == null) {
      return (
        availability: availability,
        summary: 'I could not get your position in time. Try again outside, '
            'or away from tall buildings.',
      );
    }
    return (
      availability: availability,
      summary: whereAmISentence(
        fix: fix,
        now: DateTime.now(),
        places: await store.cachedPlaces(),
        nearby: await _streetAt(fix),
      ),
    );
  }

  /// "near Rizal Street, Malolos", if the map can say quickly. A slow answer
  /// is no answer: the person asked where they are, not to wait. Nor is a
  /// street named from a position too rough to be sure which street it is.
  Future<String?> _streetAt(LocationFix fix) async {
    final search = placeSearch;
    if (search == null || fix.accuracyMetres > kPoorFixMetres) return null;
    try {
      final here = await search
          .reverse(RoutePoint(fix.latitude, fix.longitude))
          .timeout(const Duration(seconds: 4));
      return here == null ? null : nearbyDescription(here);
    } catch (_) {
      return null;
    }
  }

  /// The route the app is on, as the router last reported it.
  String? _path;

  /// Called by the router when the location changes, before the next page
  /// builds.
  ///
  /// Listening belongs to the screen that asked for it, so it stops here - not
  /// in that screen's dispose(), which runs after the next screen has started
  /// and used to cancel *its* listening: the SOS countdown's "cancel", for one.
  void routeChanged(String path) {
    if (path == _path) return;
    _path = path;
    _voice?.routeChanged(path);
    if (_state.adminCheckPending && path.startsWith(Routes.adminRoot)) {
      unawaited(recheckAdmin());
    }
  }

  // Constructed lazily so a widget test that never opens a Firestore-backed
  // screen does not need Firebase initialised.
  PairingRepository? _pairing;
  PairingRepository get pairing => _pairing ??= PairingRepository();

  AlertPresenter? _alerts;
  AlertPresenter get alerts => _alerts ??= LocalAlertPresenter();

  AdminRepository? _admin;
  AdminRepository get admin => _admin ??= AdminRepository();

  /// How often, and how far apart, an unanswered roster check is asked again
  /// before it waits for the sign-in page's Retry.
  static const int rosterRetries = 3;
  static const Duration rosterRetryGap = Duration(seconds: 3);

  Timer? _rosterRetry;
  int _rosterRetriesLeft = 0;
  bool _rosterBusy = false;

  /// Records what the roster said, and asks again later if it said nothing.
  SessionState _withRoster(SessionState state, RosterCheck roster) {
    _rosterRetry?.cancel();
    if (roster == RosterCheck.unknown && _rosterRetriesLeft > 0) {
      _rosterRetriesLeft--;
      _rosterRetry =
          Timer(rosterRetryGap, () => unawaited(recheckAdmin()));
    }
    return state.copyWith(
      isAdmin: roster == RosterCheck.admin,
      adminCheckPending: roster == RosterCheck.unknown,
    );
  }

  /// Asks the roster again, after a read that could not tell.
  ///
  /// The first answer used to be the only one: a failed read at sign-in was
  /// kept as "not an administrator" until the page was reloaded, and every
  /// sidebar click bounced to the sign-in page. Now an unanswered check is
  /// retried on its own, on a move to another dashboard page, and from the
  /// sign-in page's Retry - and only an actual refusal is remembered.
  Future<void> recheckAdmin() async {
    final uid = _state.uid;
    if (!_dashboard || uid == null || !_state.adminCheckPending) return;
    if (_rosterBusy) return;
    _rosterBusy = true;
    final RosterCheck roster;
    try {
      roster = await admin.rosterCheck(uid);
    } finally {
      _rosterBusy = false;
    }
    // Signed out, or answered some other way, while the read was out.
    if (_state.uid != uid || !_state.adminCheckPending) return;
    update(_withRoster(_state, roster));
  }

  AccountStatusRepository? _accountStatus;
  AccountStatusRepository get accountStatus =>
      _accountStatus ??= AccountStatusRepository();

  StreamSubscription<bool>? _removalWatch;
  bool _handlingRemoval = false;
  String? _notice;

  /// Why this phone was last signed out, for the welcome screen to say once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  /// Follows whether an administrator removes the signed-in account.
  void _watchRemoval(String? uid) {
    unawaited(_removalWatch?.cancel());
    _removalWatch = null;
    if (uid == null || kIsWeb) return;
    try {
      _removalWatch = accountStatus.watchRemoved(uid).listen((removed) {
        if (removed) unawaited(handleRemoval(uid));
      });
    } catch (_) {
      // No Firestore to ask - a test, or a platform without it. The sign-in
      // check still refuses a removed account on the way in.
    }
  }

  /// The account was removed from the dashboard.
  ///
  /// What the dashboard deliberately could not delete - saved places, which
  /// would have meant an administrator reading someone's home address - the
  /// phone deletes, as the owner. Then it signs out and says why.
  Future<void> handleRemoval(String uid) async {
    if (_handlingRemoval) return;
    _handlingRemoval = true;
    try {
      try {
        for (final place in await places.list(uid)) {
          await places.remove(uid, place.id);
        }
        await history.forgetAll(uid);
      } catch (_) {
        // Best effort. The rules already refuse this account every write.
      }
      _notice = kRemovedAccountNotice;
      await signOut();
      await speaker.speak(kRemovedAccountNotice);
    } finally {
      _handlingRemoval = false;
    }
  }

  AdminAccountCreator? _accountCreator;
  AdminAccountCreator get accountCreator =>
      _accountCreator ??= AdminAccountCreator();

  AuthService? _auth;
  AuthService get auth => _auth ??= AuthService();

  LocationHistoryRepository? _history;
  LocationHistoryRepository get history =>
      _history ??= LocationHistoryRepository();

  SosEngine? _sos;
  SosEngine get sos => _sos ??= SosEngine(speaker: speaker);

  SavedPlacesRepository? _places;
  SavedPlacesRepository get places =>
      _places ??= SavedPlacesRepository(store: store);

  /// Where the user has said they are going. Cleared when they arrive or
  /// stop, and by sign-out. In memory only: a destination is for a journey,
  /// not a setting.
  Destination? destination;

  final JourneyStore? _journeyStore;
  JourneyRecorder? _journeys;

  /// The journey being recorded, from choosing a destination to arriving or
  /// stopping. Its summary is what the dashboard's Overview counts.
  JourneyRecorder get journeys => _journeys ??= JourneyRecorder(
      store: _journeyStore ??
          FirestoreJourneyStore(history: () => history, admin: () => admin));

  /// Ends the journey when the app has been away this long.
  Timer? _awayTimer;

  /// Records the destination the way §2.A.7 records a journey, and remembers
  /// it for the scan screen. Best effort on the record: it needs history
  /// consent and a connection, and the directions need neither.
  ///
  /// Null ends the journey - arrived, or stopped - and publishes its
  /// summary.
  Future<void> setDestination(Destination? place) async {
    destination = place;
    notifyListeners();
    if (place != null) recordActivity(ActivityKind.journey, place.label);
    final uid = _state.uid;
    if (place == null || uid == null) {
      await journeys.end();
      return;
    }
    await journeys.start(
      uid: uid,
      consent: _state.consent['history'] == true,
      destination: place.label,
      // A name the user gave it; a place found by search is not named in
      // the summary.
      savedLabel: place.id.startsWith('search-') ? null : place.label,
    );
  }

  /// Something that happened on the way, for the journey's record.
  void recordJourneyEvent(SessionEventKind kind, {String? detail, String? key}) =>
      unawaited(journeys.recordEvent(kind, detail: detail, key: key));

  /// An obstacle warned of: told to the guardian, if they may know, and
  /// kept on the journey's record.
  void noticedObstacle(String label) {
    recordActivity(ActivityKind.obstacle, label);
    recordJourneyEvent(
        label == 'stairs'
            ? SessionEventKind.stairsDetected
            : SessionEventKind.obstacleDetected,
        detail: label,
        key: label);
  }

  /// A position the directions used, for the journey's record.
  void recordJourneyFix(LocationFix fix) => unawaited(journeys.recordFix(fix));

  /// The directions reached the place. The destination is kept - the screen
  /// still shows it - but the journey is over.
  Future<void> arrived() => journeys.end();

  GuardianRepository? _guardian;
  GuardianRepository get guardian =>
      _guardian ??= GuardianRepository(pairing: pairing);

  GuardianOnboarding? _guardianOnboarding;
  GuardianOnboarding get guardianOnboarding =>
      _guardianOnboarding ??= GuardianOnboarding(
        auth: auth,
        store: store,
        pairing: pairing,
      );

  OnboardingController? _onboarding;
  OnboardingController get onboarding => _onboarding ??= OnboardingController(
        auth: auth,
        store: store,
        pairing: pairing,
      );

  final _firstAuth = Completer<void>();

  /// Completes once Firebase has said who is signed in, or that nobody is.
  ///
  /// Until then [state.signedIn] is a placeholder. A router built on the
  /// placeholder sends a signed-in user to Welcome for the second or two the
  /// answer takes, and reads it to them. Never completes if [bindAuth] is not
  /// called, so callers put a timeout on it.
  Future<void> get firstAuth => _firstAuth.future;

  void _settleAuth() {
    if (!_firstAuth.isCompleted) _firstAuth.complete();
  }

  /// Follows Firebase auth so the router's guard reflects who is signed in.
  ///
  /// Called from app.dart once Firebase is up. Left uncalled in tests, where
  /// the session stays signed out - which is the guard failing closed.
  Future<void> bindAuth() async {
    auth.accounts.listen((user) async {
      _watchRemoval(user?.uid);
      if (user == null) {
        _rosterRetry?.cancel();
        // Read back off the device rather than carrying the old state
        // forward. Signing out clears what this phone held about that account,
        // and a listener that trusted its own memory would put it straight
        // back - including the safety acknowledgement, which belongs to the
        // person who heard the notice and not to the handset.
        update(SessionState(
          safetyAcknowledged: await store.safetyAcknowledged(),
          completedSteps: await store.completedSteps(),
        ));
        _settleAuth();
        return;
      }
      // The roster only matters on the web dashboard. Asked on a phone, it
      // is a permission-denied read on every launch for everyone who is not
      // an administrator - which is everyone with a phone.
      final roster = _dashboard
          ? await admin.rosterCheck(user.uid)
          : RosterCheck.notAdmin;
      // Which app this account is for, decided before the guard runs: a
      // guardian sent through the visually impaired flow would be asked to
      // create the account they have just created.
      final isGuardian = await _isGuardian(user.uid);
      _rosterRetriesLeft = rosterRetries;
      update(_withRoster(
        _state.copyWith(
          uid: user.uid,
          signedIn: true,
          isGuardian: isGuardian,
          needsEmailVerification: !_dashboard &&
              requiresEmailVerification(
                emailVerified: user.emailVerified,
                createdAt: user.createdAt,
              ),
        ),
        roster,
      ));
      // Best effort, and deliberately not awaited by the guard.
      unawaited(refreshProfile());
      _settleAuth();
    });
  }

  SessionState _state = const SessionState();
  SessionState get state => _state;

  /// Reads what was persisted before the first frame decides where to go.
  ///
  /// Everything here is local. A returning user with no signal reaches their
  /// dashboard with the alarm and the dialler live, because nothing on this
  /// path needs Firestore.
  Future<void> load() async {
    final profile = await store.cachedProfile();
    final handsFree = await store.handsFree();
    if (handsFree != null && handsFree != _handsFree) {
      _handsFree = handsFree;
      _voice?.handsFree = handsFree;
    }
    update(_state.copyWith(
      isGuardian: _state.isGuardian || profile.isGuardian,
      safetyAcknowledged: await store.safetyAcknowledged(),
      completedSteps: await store.completedSteps(),
      consent: profile.consent,
      contacts: profile.contacts,
      guardianCount: profile.guardianCount,
    ));
  }

  /// Re-reads the profile from Firestore and caches it.
  ///
  /// Failure is not an error: the cached values stay, which is the whole point.
  Future<void> refreshProfile() async {
    final uid = _state.uid;
    if (uid == null) return;
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data();
      if (data == null) return;
      await store.cacheProfile(CachedProfile(
        role: data['role'] as String?,
        consent: Map<String, bool>.from(data['consent'] as Map? ?? const {}),
        contacts: emergencyContactsFrom(data),
        guardianCount: await _countGuardians(uid),
      ));
      await load();
    } catch (_) {
      // Offline. The cache is what the app runs on until the network returns.
    }
  }

  /// Counted from the pairings, because nothing on the client may write a
  /// count onto the user document and nothing on the server does either.
  /// Falls back to what was cached rather than to zero: offline, "no
  /// guardian" would be a claim, and the wrong one.
  Future<int> _countGuardians(String uid) async {
    try {
      return (await pairing.guardiansOf(uid)).length;
    } catch (_) {
      return _state.guardianCount;
    }
  }

  /// The role, from the device first and the account second.
  ///
  /// The device's copy is written before an account is created and cleared
  /// at sign-out, so it is right whenever it is present. The account is read
  /// only when it is not - a sign-in on a new phone - and bounded, because
  /// this runs before the first screen and a phone with no signal must still
  /// reach one.
  Future<bool> _isGuardian(String uid) async {
    final cached = await store.cachedProfile();
    if (cached.role != null) return cached.isGuardian;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final role = snapshot.data()?['role'] as String?;
      if (role != null) await store.cacheProfile(cached.copyWith(role: role));
      return role == 'guardian';
    } catch (_) {
      return false;
    }
  }

  /// Records which app a new account is for, before it is created.
  Future<void> rememberRole(String role) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(role: role));
    await load();
  }

  /// Puts a just-saved emergency contact where SOS reads it from.
  ///
  /// The bug this closes: the contact was written to Firestore and the
  /// device's copy - the one SOS and Settings actually read - was refreshed
  /// only at sign-in. Save a contact during setup, press SOS, and the
  /// receipt said no contact was saved. The tester was right that the
  /// feature did not work; it worked on the next launch, with a network.
  Future<void> rememberContacts(List<EmergencyContact> contacts) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(contacts: dedupeContacts(contacts)));
    await load();
  }

  /// Same shape, for consent. The consent centre used to re-read Firestore
  /// after saving, which offline meant a switch that did not move.
  Future<void> rememberConsent(Map<String, bool> consent) async {
    final facesWereOn = facesConsented;
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(consent: consent));
    await load();
    // Turning recognition off is taking the faces back, not pausing.
    if (facesWereOn && consent['faces'] != true) await _forgetFaces();
  }

  void update(SessionState next) {
    final before = _state;
    _state = next;
    _syncSharing(before);
    notifyListeners();
  }

  @override
  void dispose() {
    _sharer?.stop();
    _rosterRetry?.cancel();
    _awayTimer?.cancel();
    unawaited(_removalWatch?.cancel());
    super.dispose();
  }

  /// Runs an onboarding step's work, then re-reads what is complete.
  ///
  /// The redirect sends the user to the first incomplete step, so refreshing
  /// the session *is* the navigation - there is no second source of truth for
  /// where they are in the flow.
  Future<void> advance(Future<void> Function() work) async {
    await work();
    await load();
  }

  /// Signs out, and hands the phone back the way it was found.
  ///
  /// Firebase first, because it is the only step here that can fail. Clearing
  /// the device before it would, on that failure, leave a phone with no setup
  /// on it still signed in to the account the setup belonged to — which lands
  /// the user back at "Create your account" for an account they already have.
  /// That is the loop this release exists to close, reached by another road.
  Future<void> signOut() async {
    // Before the account is gone: the faces are filed under it, and the
    // journey's summary is written as them.
    await journeys.end();
    await _forgetFaces(quietly: true);
    await auth.signOut();
    await store.forgetAccount();
    destination = null;
    await load();
  }

  Future<void> acknowledgeSafety() async {
    await store.acknowledgeSafety();
    // Everything else carries forward. This used to rebuild the state from
    // five fields and drop the rest, so every acknowledgement - on each cold
    // start, and again from Settings - emptied the contacts, consent, guardian
    // count and uid in memory until the next load(). Settings then said "SOS
    // has nobody to call", the contact screen opened blank, and a Save there
    // would have written that blank over the real contact.
    update(_state.copyWith(safetyAcknowledged: true));
  }
}

/// Lets a device run start somewhere specific without editing code:
///
///     flutter run --dart-define=START=/debug
///
/// Empty by default, so nothing about the normal launch changes.
const String _startOverride = String.fromEnvironment('START');

GoRouter createRouter(AppSession session) {
  final router = GoRouter(
      initialLocation: _startOverride.isNotEmpty
          ? _startOverride
          : (session.dashboard ? Routes.adminRoot : Routes.welcome),
      refreshListenable: session,
      redirect: (context, state) => resolveRedirect(
        isWeb: session.dashboard,
        location: state.matchedLocation,
        session: session.state,
      ),
      routes: [
        // Debug builds only. Never reachable in a release binary.
        if (kDebugMode)
          GoRoute(
            path: Routes.debug,
            builder: (_, __) => LocationDebugScreen(
              source: const GeolocatorLocationSource(),
              presenter: session.alerts,
              bestEffort: bestEffortFix,
            ),
          ),
        GoRoute(
          path: Routes.safety,
          builder: (context, _) {
            // Captured before the callback runs: once acknowledged, the state
            // says true and the screen would no longer know it had been the
            // first run.
            final firstRun = !session.state.safetyAcknowledged;
            return SafetyNoticeScreen(
              speaker: session.speaker,
              alreadyAcknowledged: !firstRun,
              onAcknowledge: () async {
                await session.acknowledgeSafety();
                if (!context.mounted) return;
                // The redirect deliberately allows /safety once acknowledged,
                // so that the dashboard can reopen it. That means nothing moves
                // the user off it here - this navigation has to be explicit.
                appNavigate(context, firstRun ? Routes.welcome : Routes.home);
              },
            );
          },
        ),

        // ---- visually impaired user app (mobile) ----
        GoRoute(
          path: Routes.welcome,
          builder: (context, _) => WelcomeScreen(
            speaker: session.speaker,
            notice: session.takeNotice(),
            onCreateAccount: () => appNavigate(context, Routes.chooseRole),
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.chooseRole,
          builder: (context, _) => ChooseRoleScreen(
            speaker: session.speaker,
            onVisuallyImpaired: () async {
              await session.rememberRole('vi');
              if (context.mounted) appNavigate(context, Routes.createAccount);
            },
            onGuardian: () => appNavigate(context, Routes.guardianRegister),
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.forgotPassword,
          builder: (context, state) => ForgotPasswordScreen(
            speaker: session.speaker,
            initialEmail: state.uri.queryParameters['email'],
            onSendReset: session.auth.sendPasswordReset,
            onBack: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.signIn,
          builder: (context, _) => SignInScreen(
            speaker: session.speaker,
            onSignIn: (email, password) async {
              final failure = await session.auth.signIn(email, password);
              if (failure != null) return failure;
              // The password is right and the account was removed. Firebase
              // still knows the sign-in; ImpairGency does not.
              final uid = session.auth.uid;
              if (uid != null &&
                  await session.accountStatus.isRemoved(uid) == true) {
                await session.signOut();
                return kRemovedAccountNotice;
              }
              // What the account has already finished, back onto this device
              // before the redirect reads it. Without this the router sees no
              // completed steps and sends a returning user to step one, to
              // create the account they have just signed in to.
              await session.onboarding.restoreProgress();
              await session.load();
              return null;
            },
            onCreateAccount: () => appNavigate(context, Routes.chooseRole),
            onForgotPassword: (email) => appNavigate(
              context,
              Uri(
                path: Routes.forgotPassword,
                queryParameters: email.isEmpty ? null : {'email': email},
              ).toString(),
            ),
          ),
        ),
        GoRoute(
          path: Routes.verifyEmail,
          builder: (context, _) => VerifyEmailScreen(
            speaker: session.speaker,
            email: session.auth.email,
            linkSent: session.auth.verificationSent ?? true,
            onCheck: session.checkEmailVerified,
            onResend: session.auth.sendVerification,
            onUseDifferentEmail: () => appNavigate(context, Routes.signOut),
          ),
        ),
        GoRoute(
          path: Routes.createAccount,
          builder: (context, _) => CreateAccountScreen(
            speaker: session.speaker,
            onCreate: (email, password) async {
              final failure =
                  await session.onboarding.createAccount(email, password);
              if (failure == null) await session.load();
              return failure;
            },
          ),
        ),
        GoRoute(
          path: Routes.profile,
          builder: (context, _) => ProfileScreen(
            speaker: session.speaker,
            onSave: (info) => session.advance(
                () => session.onboarding.savePersonalInfo(info)),
          ),
        ),
        GoRoute(
          path: Routes.preferences,
          builder: (context, _) => PreferencesScreen(
            speaker: session.speaker,
            onChoose: (on) => session.advance(
                () => session.onboarding.savePreference(screenStaysOn: on)),
            onSkip: () => session.advance(
                () => session.onboarding.skip(Routes.preferences)),
          ),
        ),
        GoRoute(
          path: Routes.emergencyContact,
          builder: (context, _) => EmergencyContactScreen(
            speaker: session.speaker,
            initial: session.state.contacts,
            picker: const SystemContactPicker(),
            onSave: (contacts) => _step(context, session, () async {
              await session.onboarding.saveEmergencyContacts(contacts);
              await session.rememberContacts(contacts);
            }),
            onSkip: () => _step(context, session,
                () => session.onboarding.skip(Routes.emergencyContact)),
          ),
        ),
        GoRoute(
          path: Routes.inviteGuardian,
          builder: (context, _) => FutureBuilder<String?>(
            future: session.onboarding.issueGuardianCode(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              final code = snapshot.data;
              if (code == null) {
                // Never a fabricated code: a guardian entering one that was
                // never issued would fail with no way to tell why.
                return _CouldNotIssueCode(
                  speaker: session.speaker,
                  onSkip: () => _step(context, session,
                      () => session.onboarding.skip(Routes.inviteGuardian)),
                );
              }
              return InviteGuardianScreen(
                speaker: session.speaker,
                code: code,
                onDone: () => _step(context, session,
                    session.onboarding.markGuardianInvited),
                onSkip: () => _step(context, session,
                    () => session.onboarding.skip(Routes.inviteGuardian)),
              );
            },
          ),
        ),
        GoRoute(
          path: Routes.consent,
          builder: (context, _) => ConsentScreen(
            speaker: session.speaker,
            onContinue: (values) => session.advance(() async {
              await session.onboarding.saveConsent(values);
              await session.rememberConsent(values);
            }),
          ),
        ),
        GoRoute(
          path: Routes.device,
          builder: (context, _) => DeviceScreen(
            speaker: session.speaker,
            onHasDevice: () => _step(context, session,
                () => session.onboarding.saveDevice(hasDevice: true)),
            onNoDevice: () => _step(context, session,
                () => session.onboarding.saveDevice(hasDevice: false)),
            onSkip: () => _step(context, session,
                () => session.onboarding.skip(Routes.device)),
          ),
        ),
        GoRoute(
          path: Routes.allSet,
          builder: (context, _) => FutureBuilder<({bool contact, bool guardian})>(
            future: session.onboarding.whatIsSetUp(),
            builder: (context, snapshot) {
              final state = snapshot.data ?? (contact: false, guardian: false);
              return AllSetScreen(
                speaker: session.speaker,
                hasEmergencyContact: state.contact,
                hasGuardian: state.guardian,
                onStart: () => session.advance(session.onboarding.finish),
              );
            },
          ),
        ),
        GoRoute(
          path: Routes.home,
          builder: (context, _) => DashboardScreen(
            speaker: session.speaker,
            voice: session.voice,
            consent: session.state.consent,
            onScan: () => appNavigate(context, Routes.scan),
            onAssist: () => appNavigate(context, Routes.assist),
            onReadText: () => appNavigate(context, Routes.readText),
            onSos: () => appNavigate(context, Routes.sos),
            onWhatCanISay: () => appNavigate(context, Routes.whatCanISay),
            onSettings: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.scan,
          builder: (context, _) {
            // Once per visit: the friends watched, and anyone to meet.
            final friends = session.friendRecognition();
            final meet = session.takePendingFriend();
            return ScanScreen(
              speaker: session.prioritySpeaker,
              voice: session.voice,
              friends: friends,
              meetFriend: meet,
              onObstacle: session.noticedObstacle,
              onBack: () => appNavigate(context, Routes.home),
            );
          },
        ),
        GoRoute(
          path: Routes.journey,
          // Nowhere to go is Smart assistance's question, not a blank map.
          redirect: (_, __) =>
              session.destination == null ? Routes.assist : null,
          builder: (context, _) {
            final friends = session.friendRecognition();
            // Rebuilt when the destination changes: "take me to" said on this
            // screen goes to the route it is already on, which the router
            // does not rebuild by itself.
            return _SessionSelector<Destination?>(
              session: session,
              select: (session) => session.destination,
              builder: (destination) => destination == null
                  ? const Scaffold(backgroundColor: AppColors.navy)
                  : JourneyScreen(
                      speaker: session.prioritySpeaker,
                      voice: session.voice,
                      destination: destination,
                      positions: const GeolocatorLocationSource().positions(),
                      routing: session.routing,
                      friends: friends,
                      onObstacle: session.noticedObstacle,
                      onFix: session.recordJourneyFix,
                      onGuidance: (sentence) => session.recordJourneyEvent(
                          SessionEventKind.guidanceGiven,
                          detail: sentence),
                      onArrived: () => unawaited(session.arrived()),
                      // A real move to Scan, which keeps warning. The screen
                      // used to stay where it was and forget the destination
                      // itself, because a go() to the route already open is a
                      // no-op - and forgetting it by hand kept going wrong.
                      // Leaving first, then clearing, so this route is never
                      // asked to show a journey to nowhere.
                      onStop: () async {
                        appNavigate(context, Routes.scan);
                        await session.setDestination(null);
                      },
                      onBack: () async {
                        appNavigate(context, Routes.home);
                        await session.setDestination(null);
                      },
                    ),
            );
          },
        ),
        GoRoute(
          path: Routes.readText,
          builder: (context, _) => ReadTextScreen(
            speaker: session.speaker,
            voice: session.voice,
            onRead: (text) => session.recordActivity(ActivityKind.textRead, text),
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.assist,
          builder: (context, _) => AdminFreeFuture<List<Destination>>(
            load: () => session.places.list(session.state.uid ?? ''),
            builder: (_, places) => VoiceScopeHost(
              voice: session.voice,
              scope: VoiceScope(
                commands: () => kAssistCommands,
                // A saved place's name said on its own - "home", "the
                // clinic" - is the answer to this screen's question.
                onWords: (words) async {
                  final place = savedPlaceNamed(words, places);
                  if (place == null) return false;
                  await session.speaker.speak('Directions to ${place.label}.');
                  await session.setDestination(place);
                  if (context.mounted) appNavigate(context, Routes.journey);
                  return true;
                },
              ),
              child: SmartAssistanceScreen(
                speaker: session.speaker,
                voice: session.voice,
                search: session.placeSearch == null
                    ? null
                    : session.searchPlaces,
                places: places,
                onGo: (place) async {
                  await session.setDestination(place);
                  if (context.mounted) appNavigate(context, Routes.journey);
                },
                onManagePlaces: () => appNavigate(context, Routes.savedPlaces),
                onBack: () => appNavigate(context, Routes.home),
              ),
            ),
          ),
        ),
        GoRoute(
          path: Routes.savedPlaces,
          // Reloaded after every change. Going to this route again, which is
          // what it did, is a no-op for the router: the list stayed as it was
          // until the screen was left and opened again.
          builder: (context, _) => _Reloading<List<Destination>>(
            load: () => session.places.list(session.state.uid ?? ''),
            builder: (_, places, reload) => SavedPlacesScreen(
              speaker: session.speaker,
              places: places,
              onSaveHere: (kind, label) async {
                final failure = await _saveHere(session, kind, label);
                if (failure == null) await reload();
                return failure;
              },
              onRename: (place, label) async {
                await session.places
                    .save(session.state.uid ?? '', place.copyWith(label: label));
                await reload();
              },
              onRemove: (place) async {
                await session.places.remove(session.state.uid ?? '', place.id);
                await reload();
              },
              search: session.placeSearch == null ? null : session.searchPlaces,
              onSaveFound: (place) async {
                await session.places.save(session.state.uid ?? '',
                    place.copyWith(label: shortPlaceLabel(place.label)));
                await reload();
                return null;
              },
              onBack: () => appNavigate(context, Routes.settings),
            ),
          ),
        ),
        GoRoute(
          path: Routes.people,
          builder: (context, _) => _Reloading<List<Friend>>(
            load: () => session.friendStore.load(session.faceOwner),
            builder: (_, friends, reload) => PeopleScreen(
              speaker: session.speaker,
              friends: friends,
              consented: session.facesConsented,
              onForget: (friend) async {
                await session.friendStore.save(session.faceOwner,
                    [for (final f in friends) if (f.id != friend.id) f]);
                await reload();
              },
              onForgetEveryone: () async {
                await session.friendStore.deleteAll(session.faceOwner);
                await reload();
              },
              onBack: () => appNavigate(context, Routes.settings),
            ),
          ),
        ),
        GoRoute(
          path: Routes.sos,
          builder: (context, _) => SosFlow(
            engine: session.sos,
            userId: session.state.uid,
            speaker: session.speaker,
            voiceController: session.voice,
            contacts: session.state.contacts,
            guardianCount: session.state.guardianCount,
            onEvent: (kind) => session.recordJourneyEvent(kind),
            onFinished: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (context, _) => _SessionSelector<bool>(
            session: session,
            select: (session) => session.handsFree,
            builder: (handsFree) => SettingsScreen(
              speaker: session.speaker,
              handsFree: handsFree,
              onToggleHandsFree: () async {
                final on = !session.handsFree;
                await session.setHandsFree(on);
                await session.speaker.speak(on
                    ? 'Hands-free voice is on. The app listens on every '
                        "screen, for commands and buttons' names."
                    : 'Hands-free voice is off. Tap to speak before each '
                        'command.');
              },
              contactCount: session.state.contacts.length,
              hasGuardian: session.state.guardianCount > 0,
              onConsent: () => appNavigate(context, Routes.consentCentre),
              onLearned: () => appNavigate(context, Routes.learned),
              onSavedPlaces: () => appNavigate(context, Routes.savedPlaces),
              onPeople: () => appNavigate(context, Routes.people),
              onDevice: () => appNavigate(context, Routes.device),
              onEmergencyContact: () =>
                  appNavigate(context, Routes.emergencyContact),
              onInviteGuardian: () =>
                  appNavigate(context, Routes.inviteGuardian),
              onSafetyNotice: () => appNavigate(context, Routes.safety),
              onSignOut: () => appNavigate(context, Routes.signOut),
              onBack: () => appNavigate(context, Routes.home),
            ),
          ),
        ),
        GoRoute(
          path: Routes.signOut,
          builder: (context, _) => SignOutScreen(
            speaker: session.speaker,
            // No navigation afterwards: signing out makes the redirect true
            // again, and it sends them to the safety notice and then the
            // welcome screen on its own.
            onSignOut: session.signOut,
            onCancel: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.consentCentre,
          builder: (context, _) => ConsentCentreScreen(
            speaker: session.speaker,
            current: session.state.consent,
            onSave: (values) async {
              await session.onboarding.saveConsent(values);
              await session.rememberConsent(values);
              unawaited(session.refreshProfile());
            },
            onBack: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.learned,
          builder: (context, _) => AdminFreeFuture<List<Place>>(
            load: () => session.history.places(session.state.uid ?? ''),
            builder: (_, places) => LearnedDataScreen(
              speaker: session.speaker,
              places: places,
              offset: DateTime.now().timeZoneOffset,
              onForgetAll: () async {
                await session.history.forgetAll(session.state.uid ?? '');
                if (context.mounted) appNavigate(context, Routes.settings);
              },
              onForgetPlace: (place) async {
                await session.history
                    .forgetPlace(session.state.uid ?? '', place);
                if (context.mounted) appNavigate(context, Routes.learned);
              },
              onBack: () => appNavigate(context, Routes.settings),
            ),
          ),
        ),
        GoRoute(
          path: Routes.whatCanISay,
          builder: (context, _) => WhatCanISayScreen(
            speaker: session.speaker,
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),

        // ---- guardian app (mobile) ----
        GoRoute(
          path: Routes.guardianHome,
          builder: (context, _) => GuardianHomePage(
            guardianId: session.state.uid ?? '',
            repository: session.guardian,
            presenter: session.alerts,
            speaker: session.speaker,
            onEnterCode: () => appNavigate(context, Routes.guardianAccept),
            onSignOut: () => appNavigate(context, Routes.signOut),
            onLiveLocation: (user) => appNavigate(
                context, '${Routes.guardianLive}?uid=${user.uid}'),
          ),
        ),
        GoRoute(
          path: Routes.guardianLive,
          builder: (context, state) {
            final uid = state.uri.queryParameters['uid'];
            return LiveLocationScreen(
              user: session.guardian
                  .watch(session.state.uid ?? '')
                  .map((users) => users
                      .cast<WatchedUser?>()
                      .firstWhere((u) => u!.uid == uid, orElse: () => null)),
              onBack: () => appNavigate(context, Routes.guardianHome),
              onOpenMap: (fix) => launchUrl(mapLinkFor(fix),
                  mode: LaunchMode.externalApplication),
            );
          },
        ),
        GoRoute(
          path: Routes.guardianRegister,
          builder: (context, _) => GuardianRegisterScreen(
            speaker: session.speaker,
            onRegister: (registration) async {
              final failure =
                  await session.guardianOnboarding.register(registration);
              await session.load();
              return failure;
            },
            // The redirect lets a signed-in guardian stay on this form, so a
            // refused code can be corrected; leaving it on success is this
            // callback's job. Without it the tester's registration worked and
            // nothing on screen changed.
            onRegistered: () => appNavigate(context, Routes.guardianHome),
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.guardianAccept,
          builder: (context, _) => AcceptInvitationScreen(
            onRedeem: (code) => _redeem(session, code),
            onAccepted: () => appNavigate(context, Routes.guardianHome),
            onBack: () => appNavigate(context, Routes.guardianHome),
          ),
        ),

        // ---- admin dashboard (web) ----
        _page(Routes.adminRoot, 'Admin', 'Phase 3', 'Overview'),
        GoRoute(
          path: Routes.adminSignIn,
          // Rebuilt from the session, not only from the route. For an account
          // off the roster the redirect rightly says "stay", so the route never
          // changed, nothing rebuilt the screen with who had signed in, and the
          // form just sat there looking like a wrong password.
          builder: (_, __) =>
              _SessionSelector<({String? signedInAs, bool checking})>(
            session: session,
            // Present only when authentication worked and the roster check
            // did not - refused, or not yet answered. The screen explains
            // itself instead of silently reappearing. Rebuilt only when this
            // changes, so typing into the form is never interrupted by a
            // session update it does not need.
            select: (session) => (
              signedInAs: session.state.signedIn && !session.state.isAdmin
                  ? (session.auth.email ?? 'this account')
                  : null,
              checking: session.state.adminCheckPending,
            ),
            builder: (roster) => AdminSignInScreen(
              onSignIn: (email, password) =>
                  session.auth.signIn(email, password),
              signedInAs: roster.signedInAs,
              signedInUid: session.state.uid,
              checkingRoster: roster.checking,
              onCheckAgain: session.recheckAdmin,
              onSignOut: () => session.auth.signOut(),
            ),
          ),
        ),
        GoRoute(
          path: Routes.adminOverview,
          builder: (context, _) => AdminPage<UsageOverview>(
            route: Routes.adminOverview,
            title: 'Overview',
            subtitle: 'Last 30 days',
            load: session.admin.overview,
            // Journeys are recorded only with history on, so no journeys is
            // not an empty page: emergencies and active users are counted
            // without them, and the page says why the rest is blank.
            isEmpty: (data) =>
                data.sessions == 0 &&
                data.sosIncidents == 0 &&
                data.activeUsers == 0,
            emptyTitle: 'Nothing recorded in the last 30 days',
            emptyDetail: 'No journeys, emergencies or shared positions. '
                'Journeys are recorded only for users who turned history on.',
            builder: (_, data, __) => OverviewScreen(overview: data),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminUsers,
          builder: (context, _) => AdminPage<
              ({List<AdminUserRow> users, List<UserInvite> invites})>(
            route: Routes.adminUsers,
            title: 'Users',
            subtitle: 'Visually impaired users, guardians and administrators',
            load: () async {
              final results = await Future.wait([
                session.admin.users(),
                session.admin.pendingInvites(),
              ]);
              return (
                users: results[0] as List<AdminUserRow>,
                invites: results[1] as List<UserInvite>,
              );
            },
            // Each action reloads the page itself. They used to navigate to
            // the page they were already on, which go_router ignores, so an
            // invitation sent never appeared in the list.
            builder: (context, data, reload) => UsersScreen(
              users: data.users,
              invites: data.invites,
              onInvite: () => _adminAction(context, reload, () async {
                final request = await showInviteDialog(context);
                if (request == null) return null;
                await session.admin.invite(
                  email: request.email,
                  role: request.role,
                  deviceId: request.deviceId,
                  invitedBy: session.state.uid,
                );
                return 'Invitation sent to ${request.email}.';
              }),
              onWithdraw: (invite) => _adminAction(context, reload, () async {
                await session.admin.withdrawInvite(invite.email);
                return 'Invitation to ${invite.email} withdrawn.';
              }),
              onAdd: () => _adminAction(context, reload, () async {
                final account = await showAddAccountDialog(context);
                if (account == null) return null;
                final result = await session.accountCreator.create(account);
                return switch (result) {
                  AccountCreated() => 'Account added. ${account.email} has '
                      'been sent a link to choose a password.',
                  AccountNotCreated(:final message, :final code) =>
                    code == 'email-already-in-use' &&
                            await session.admin.wasRemoved(account.email)
                        ? 'That email belongs to a removed account. Delete its '
                            'sign-in record in the Firebase console first, or '
                            'use a different email.'
                        : message,
                };
              }),
              onEdit: (user) => _adminAction(context, reload, () async {
                final changes = await showEditAccountDialog(context, user);
                if (changes == null) return null;
                await session.admin.updateUser(user, changes,
                    adminUid: session.state.uid ?? '');
                return 'Saved changes to ${user.name}.';
              }),
              onRemove: (user) => _adminAction(context, reload, () async {
                if (!await confirmRemoveAccount(context, user)) return null;
                await session.admin
                    .removeUser(user, adminUid: session.state.uid ?? '');
                return '${user.name} was removed.';
              }),
            ),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminHealth,
          builder: (context, _) => AdminPage<
              ({
                UsageOverview overview,
                List<SessionSummary> flagged,
                List<SosRecord> sos,
                Map<String, String> names,
              })>(
            route: Routes.adminHealth,
            title: 'System health',
            subtitle: 'What can be measured without a server',
            load: () async {
              final results = await Future.wait([
                session.admin.overview(),
                session.admin.sessionsNeedingAttention(),
                session.admin.sosEvents(),
                session.admin.users(),
              ]);
              return (
                overview: results[0] as UsageOverview,
                flagged: results[1] as List<SessionSummary>,
                sos: results[2] as List<SosRecord>,
                names: {
                  for (final user in results[3] as List<AdminUserRow>)
                    user.uid: user.name,
                },
              );
            },
            builder: (context, data, reload) => SystemHealthScreen(
              overview: data.overview,
              sessionsNeedingAttention: data.flagged,
              sosEvents: data.sos,
              userNames: data.names,
              onResolve: (record) => _adminAction(context, reload, () async {
                await session.admin
                    .resolveSos(record.id, adminUid: session.state.uid ?? '');
                return 'Marked resolved.';
              }),
            ),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminAccessibility,
          builder: (context, _) => AdminShell(
            current: Routes.adminAccessibility,
            title: 'Accessibility results',
            subtitle: 'Measured, not audited',
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
            child: const AccessibilityScreen(),
          ),
        ),
      ],
    );
  // A spoken "help" has to end up on the SOS screen. The controller is
  // app-wide and the router is the only thing that can move the user, so it
  // is wired here rather than in a screen.
  session.navigate = router.go;
  router.routerDelegate.addListener(() => session
      .routeChanged(router.routerDelegate.currentConfiguration.uri.path));
  return router;
}

GoRoute _page(String path, String title, String phase, String requirement) =>
    GoRoute(
      path: path,
      builder: (_, __) =>
          PendingScreen(title: title, phase: phase, requirement: requirement),
    );


/// Redeems a code as the signed-in guardian.
///
/// Returns null on success, or the sentence to show. Lives here rather than in
/// the screen so the screen stays testable without Firestore.
Future<String?> _redeem(AppSession session, String code) async {
  final guardianId = session.state.uid;
  if (guardianId == null) {
    return 'Sign in first, then enter the code they gave you.';
  }
  final result = await session.pairing.redeem(code, guardianId: guardianId);
  return switch (result) {
    RedeemSucceeded() => null,
    RedeemFailed(:final spoken) => spoken,
  };
}

/// Saves the current position under [kind]. Returns null, or why not.
///
/// Waits longer than the SOS location budget - nobody is in danger here,
/// and a place saved from a cell-tower guess is a Home button that points
/// at the wrong street.
Future<String?> _saveHere(
    AppSession session, DestinationKind kind, String label) async {
  const source = GeolocatorLocationSource();
  final availability = await source.requestPermission();
  if (availability != LocationAvailability.ready) {
    return permissionGuidance(availability);
  }
  final fix = await source.currentFix(timeout: const Duration(seconds: 15));
  if (fix == null) {
    return 'Could not get your position. Try again outdoors, or near a '
        'window.';
  }
  if (fix.accuracyMetres > 100) {
    return 'Your position is only known to about ${fix.accuracyMetres.round()} '
        'metres. Wait a moment and try again.';
  }
  final uid = session.state.uid ?? '';
  final id = destinationIdFor(kind,
      fresh: () => 'place-${DateTime.now().millisecondsSinceEpoch}');
  await session.places.save(
    uid,
    Destination(
      id: id,
      label: label,
      latitude: fix.latitude,
      longitude: fix.longitude,
      kind: kind,
    ),
  );
  return null;
}

/// Loads once, shows what it loaded, and loads again when told to.
class _Reloading<T> extends StatefulWidget {
  const _Reloading({required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(
      BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<_Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<_Reloading<T>> {
  T? _data;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final data = await widget.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.builder(context, _data as T, _reload);
  }
}

/// Rebuilds [builder] when [select] of the session changes - and only then.
class _SessionSelector<T> extends StatefulWidget {
  const _SessionSelector({
    super.key,
    required this.session,
    required this.select,
    required this.builder,
  });

  final AppSession session;
  final T Function(AppSession session) select;
  final Widget Function(T value) builder;

  @override
  State<_SessionSelector<T>> createState() => _SessionSelectorState<T>();
}

class _SessionSelectorState<T> extends State<_SessionSelector<T>> {
  late T _value = widget.select(widget.session);

  void _changed() {
    final next = widget.select(widget.session);
    if (next == _value) return;
    setState(() {
      _value = next;
    });
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_value);
}

/// Runs a dashboard action: whatever it reports is shown, a failure is
/// shown in words rather than swallowed, and the page reloads either way.
Future<void> _adminAction(
  BuildContext context,
  Future<void> Function() reload,
  Future<String?> Function() action,
) async {
  String? outcome;
  try {
    outcome = await action();
  } catch (e) {
    debugPrint('Dashboard action failed: $e');
    outcome = 'That did not work: the database refused it, or the connection '
        'dropped. Nothing is half done that trying again will not finish.';
  }
  if (outcome == null) return;
  await reload();
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(outcome),
    behavior: SnackBarBehavior.floating,
    width: 460,
  ));
}

/// Extracted so the navigation on success is one named thing rather than an
/// inline closure inside a route table.
void appNavigate(BuildContext context, String location) =>
    GoRouter.of(context).go(location);

/// Runs an onboarding step that Settings can reopen once setup is done.
///
/// During onboarding the refreshed session is the navigation: the redirect
/// moves the user to the next incomplete step. After setup nothing does - the
/// redirect lets [Routes.revisitable] through on purpose - so a step reopened
/// from Settings has to send the user back there itself.
Future<void> _step(
  BuildContext context,
  AppSession session,
  Future<void> Function() work,
) async {
  final revisiting = session.state.setupComplete;
  await session.advance(work);
  if (revisiting && context.mounted) appNavigate(context, Routes.settings);
}


/// Shown when a pairing code could not be issued.
///
/// The alternative - showing a made-up code - would send a guardian to type
/// something that was never issued, and fail with no way to tell why.
class _CouldNotIssueCode extends StatelessWidget {
  const _CouldNotIssueCode({required this.speaker, required this.onSkip});

  final Speaker speaker;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        step: 'Step 5 of 7',
        title: 'Could not create an invitation',
        body: const [
          'This usually means there is no connection. You can invite a guardian '
              'later from settings.',
        ],
        actions: [
          ViButton(
            label: 'Continue without a guardian',
            icon: Icons.arrow_forward,
            onPressed: onSkip,
          ),
        ],
      );
}


/// Loads something for a screen in the visually impaired app.
///
/// Named for what it is not: the dashboard's [AdminPage] shows a spinner and a
/// refusal message, which is right for a sighted operator. Here a failure falls
/// through to an empty result instead, because a blind user stuck on a spinner
/// has no way to know that is what they are looking at.
class AdminFreeFuture<T> extends StatelessWidget {
  const AdminFreeFuture({
    super.key,
    required this.load,
    required this.builder,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            // An empty list reads as "nothing learned yet", which is true
            // enough offline and better than a dead end.
            return builder(context, <Never>[] as T);
          }
          return builder(context, data);
        },
      );
}
