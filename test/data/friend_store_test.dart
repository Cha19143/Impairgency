import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/faces.dart';
import 'package:impairgency/data/friend_store_io.dart';

void main() {
  late Directory base;
  late List<String> excluded;
  late FileFriendStore store;

  final sam = Friend(
    id: 'f1',
    name: 'Sam',
    embeddings: [l2Normalize([1, 2, 3]), l2Normalize([1, 2, 2.5])],
    savedAt: DateTime.utc(2026, 9, 15, 9),
  );

  setUp(() async {
    base = await Directory.systemTemp.createTemp('faces');
    excluded = [];
    store = FileFriendStore(
      directory: () async => base,
      excludeFromBackup: (folder) async => excluded.add(folder.path),
    );
  });

  tearDown(() => base.delete(recursive: true));

  test('friends are written to this phone and read back', () async {
    await store.save('user-1', [sam]);
    final again = await store.load('user-1');
    expect(again.single.name, 'Sam');
    expect(again.single.embeddings, sam.embeddings);
    expect(File('${base.path}/faces/user-1.json').existsSync(), isTrue);
    expect(File('${base.path}/faces/user-1.json.tmp').existsSync(), isFalse,
        reason: 'written whole, then renamed into place');
  });

  test('the folder is kept out of backups before anything is written', () async {
    await store.save('user-1', [sam]);
    expect(excluded, isNotEmpty);
    expect(excluded.first, '${base.path}/faces');
  });

  test("one account's friends are not another's", () async {
    await store.save('user-1', [sam]);
    expect(await store.load('user-2'), isEmpty);
  });

  test('a file that cannot be read is no friends, not a crash', () async {
    await Directory('${base.path}/faces').create();
    await File('${base.path}/faces/user-1.json').writeAsString('{not json');
    expect(await store.load('user-1'), isEmpty);
  });

  test('deleting says how many, and leaves nothing behind', () async {
    await store.save('user-1', [sam, Friend(id: 'f2', name: 'Ana', embeddings: sam.embeddings, savedAt: sam.savedAt)]);
    expect(await store.deleteAll('user-1'), 2);
    expect(Directory('${base.path}/faces').listSync(), isEmpty);
    expect(await store.deleteAll('user-1'), 0);
  });

  test('an account id cannot reach outside the folder', () async {
    await store.save('../../etc', [sam]);
    expect(File('${base.path}/faces/______etc.json').existsSync(), isTrue);
  });
}
