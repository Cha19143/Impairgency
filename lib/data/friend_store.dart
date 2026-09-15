/// Picks the right [FileFriendStore] for the platform. The web keeps no faces.
library;

export 'friend_store_stub.dart' if (dart.library.io) 'friend_store_io.dart';
