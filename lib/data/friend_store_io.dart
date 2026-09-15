import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/vision/faces.dart';

/// Saved friends, in a file in the app's own folder on this phone.
///
/// Never uploaded, and kept out of the phone's backups: Android's backup rules
/// (`res/xml/data_extraction_rules.xml`, `backup_rules.xml`) leave out the
/// `faces` folder, and on iOS the folder is marked excluded before anything is
/// written to it. A face someone agreed to have remembered on one phone does
/// not turn up on a new one, or in a cloud.
///
/// One file per account, written whole to a temporary file and renamed over
/// the old one, so a phone that dies mid-write keeps the last good list. A
/// file that cannot be read is treated as no friends rather than an error:
/// the app has to go on warning about obstacles either way.
class FileFriendStore implements FriendStore {
  FileFriendStore({
    Future<Directory> Function()? directory,
    Future<void> Function(Directory folder)? excludeFromBackup,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _excludeFromBackup = excludeFromBackup ?? _excludeOnIos;

  final Future<Directory> Function() _directory;
  final Future<void> Function(Directory folder) _excludeFromBackup;

  static const _channel = MethodChannel('ph.impairgency/backup');

  static Future<void> _excludeOnIos(Directory folder) async {
    if (!Platform.isIOS) return;
    try {
      await _channel
          .invokeMethod<void>('excludeFromBackup', {'path': folder.path});
    } catch (e) {
      debugPrint('Could not exclude saved faces from backup: $e');
    }
  }

  Future<File> _file(String owner) async {
    final base = await _directory();
    final folder = Directory('${base.path}/faces');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    // Every time, not only on creation: a folder made by an older version, or
    // restored from somewhere, is marked too.
    await _excludeFromBackup(folder);
    final safe = owner.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${folder.path}/${safe.isEmpty ? 'local' : safe}.json');
  }

  @override
  Future<List<Friend>> load(String owner) async {
    try {
      final file = await _file(owner);
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return [
        for (final entry in raw) ?Friend.fromJson(entry),
      ];
    } catch (e) {
      debugPrint('Saved faces could not be read: $e');
      return const [];
    }
  }

  @override
  Future<void> save(String owner, List<Friend> friends) async {
    final file = await _file(owner);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
        jsonEncode([for (final f in friends) f.toJson()]),
        flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<int> deleteAll(String owner) async {
    final count = (await load(owner)).length;
    final file = await _file(owner);
    if (await file.exists()) await file.delete();
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
    return count;
  }
}
