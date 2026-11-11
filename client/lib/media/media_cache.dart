import 'dart:typed_data';

import '../core/api.dart';

/// Process-local media bytes. Display size decoding stays in the widget
/// (`cacheWidth`); this only avoids refetching the same id in one session.
class MediaCache {
  MediaCache._();
  static final _bytes = <String, Future<Uint8List>>{};

  static Future<Uint8List> load(ChatApi api, String id) =>
      _bytes[id] ??= api.media(id);

  static void forget(String id) => _bytes.remove(id);
}
