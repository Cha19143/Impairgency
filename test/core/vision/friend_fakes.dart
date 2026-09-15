import 'package:impairgency/core/vision/faces.dart';

/// Friends kept in memory, for tests.
class MemoryStore implements FriendStore {
  final Map<String, List<Friend>> saved = {};
  int saves = 0;

  @override
  Future<List<Friend>> load(String owner) async => saved[owner] ?? const [];

  @override
  Future<void> save(String owner, List<Friend> friends) async {
    saves++;
    saved[owner] = [...friends];
  }

  @override
  Future<int> deleteAll(String owner) async => saved.remove(owner)?.length ?? 0;
}
