import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/navigation/destination.dart';
import '../core/session_store.dart';

/// Home, work, school and the rest: `users/{uid}/saved_places/{id}`.
///
/// Cached on the device through the session store, for the same reason the
/// emergency contacts are: a destination button that needs the network to
/// know where Home is fails in exactly the place - a basement, a bus - it
/// is most wanted.
class SavedPlacesRepository {
  SavedPlacesRepository({
    required SessionStore store,
    FirebaseFirestore? firestore,
  })  : _store = store,
        _firestore = firestore;

  final SessionStore _store;
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _places(String uid) =>
      _db.collection('users').doc(uid).collection('saved_places');

  /// What is cached, then what the server says if it can be reached.
  Future<List<Destination>> list(String uid) async {
    try {
      final snap = await _places(uid).get().timeout(const Duration(seconds: 6));
      final places = snap.docs
          .map((d) => Destination.fromJson(d.id, d.data()))
          .nonNulls
          .toList();
      await _store.cachePlaces(places);
      return places;
    } catch (_) {
      return _store.cachedPlaces();
    }
  }

  /// Saves, replacing any place with the same id - so Home stays one Home.
  Future<void> save(String uid, Destination place) async {
    final cached = await _store.cachedPlaces();
    await _store.cachePlaces([
      ...cached.where((p) => p.id != place.id),
      place,
    ]);
    // Not awaited past the cache: a Firestore write completes on server
    // acknowledgement, which offline is never, and the button is wanted
    // offline. The SDK queues it.
    _places(uid).doc(place.id).set(place.toJson()).catchError((_) {});
  }

  Future<void> remove(String uid, String placeId) async {
    final cached = await _store.cachedPlaces();
    await _store.cachePlaces(cached.where((p) => p.id != placeId).toList());
    _places(uid).doc(placeId).delete().catchError((_) {});
  }
}
