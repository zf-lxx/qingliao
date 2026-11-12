import 'dart:io';
import 'dart:typed_data';

/// Memory + disk cache keyed by media id. Survives process death in [root].
class MediaCache {
  MediaCache({Directory? root, this.maxFiles = 400}) : _overrideRoot = root;
  final Directory? _overrideRoot;
  final int maxFiles;
  final _bytes = <String, Future<Uint8List>>{};
  Directory? _dir;

  static final instance = MediaCache();

  Future<Directory> rootDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final override = _overrideRoot;
    if (override != null) {
      await override.create(recursive: true);
      return _dir = override;
    }
    final dir = Directory('${Directory.systemTemp.path}/qingliao-media');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  File _file(Directory dir, String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${dir.path}/$safe');
  }

  Future<Uint8List> load(String id, Future<Uint8List> Function() fetch) =>
      _bytes[id] ??= _load(id, fetch);

  Future<Uint8List> _load(String id, Future<Uint8List> Function() fetch) async {
    final dir = await rootDir();
    final file = _file(dir, id);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    final bytes = await fetch();
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _trim(dir);
    } catch (_) {}
    return bytes;
  }

  Future<void> _trim(Directory dir) async {
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    if (files.length <= maxFiles) return;
    for (final extra in files.take(files.length - maxFiles)) {
      try {
        extra.deleteSync();
      } catch (_) {}
    }
  }

  void forget(String id) {
    _bytes.remove(id);
    final dir = _dir;
    if (dir == null) return;
    try {
      _file(dir, id).deleteSync();
    } catch (_) {}
  }
}
