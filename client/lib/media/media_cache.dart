import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/api.dart';

/// Memory + disk cache. Same media id is not re-downloaded after process death.
class MediaCache {
  MediaCache._();
  static final _bytes = <String, Future<Uint8List>>{};
  static Directory? _dir;
  static const _maxFiles = 400;

  static Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final dir = Directory(p.join(Directory.systemTemp.path, 'qingliao-media'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  static Future<Uint8List> load(ChatApi api, String id) =>
      _bytes[id] ??= _load(api, id);

  static Future<Uint8List> _load(ChatApi api, String id) async {
    final file = File(p.join((await _root()).path, id));
    if (await file.exists()) {
      return file.readAsBytes();
    }
    final bytes = await api.media(id);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _trim();
    } catch (_) {}
    return bytes;
  }

  static Future<void> _trim() async {
    final dir = _dir;
    if (dir == null) return;
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    if (files.length <= _maxFiles) return;
    for (final extra in files.take(files.length - _maxFiles)) {
      try {
        extra.deleteSync();
      } catch (_) {}
    }
  }

  static void forget(String id) {
    _bytes.remove(id);
    final dir = _dir;
    if (dir == null) return;
    try {
      File(p.join(dir.path, id)).deleteSync();
    } catch (_) {}
  }
}
