import '../core/vision/faces.dart';

/// The web recognises nobody, and so keeps nobody.
class FileFriendStore implements FriendStore {
  FileFriendStore();

  @override
  Future<List<Friend>> load(String owner) async => const [];

  @override
  Future<void> save(String owner, List<Friend> friends) async {}

  @override
  Future<int> deleteAll(String owner) async => 0;
}
