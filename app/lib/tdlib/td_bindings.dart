//
//  td_bindings.dart
//
//  轻聊 (Qingliao) build: TDLib is NOT shipped. This file keeps the original
//  `TdBindings` surface used by `TdClient` (createClientId / send / receive /
//  execute) but answers every request in pure Dart through
//  [QlTdEngine], which translates TDLib-JSON requests into calls to the
//  Qingliao backend (REST + WebSocket) and emits TDLib-shaped updates.
//
//  Events are delivered directly to the main-isolate router registered with
//  [listener]; there is no receive isolate. When no listener is attached the
//  events are queued and can be drained with [receive] (used by tests).
//

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../qingliao/ql_engine.dart';
import 'td_session_string.dart';

class TdBindings {
  TdBindings._();

  static final TdBindings _shared = TdBindings._();

  /// All callers share one in-process "library", like the process-global
  /// tdjson it replaces.
  factory TdBindings.open() => _shared;

  final Map<int, QlTdEngine> _engines = {};
  final Queue<Map<String, dynamic>> _queue = Queue();
  int _nextClientId = 0;

  void Function(Map<String, dynamic> event)? _listener;

  /// Routes every emitted event to [listener] (on the main isolate). Queued
  /// events are flushed immediately.
  set listener(void Function(Map<String, dynamic> event)? value) {
    _listener = value;
    if (value == null) return;
    while (_queue.isNotEmpty) {
      value(_queue.removeFirst());
    }
  }

  bool get supportsSessionStringBackup => true;
  bool get supportsTransferBoost => false;

  int createClientId() {
    final id = ++_nextClientId;
    _engines[id] = QlTdEngine(clientId: id, emit: (event) => _emit(id, event));
    return id;
  }

  QlTdEngine? engine(int clientId) => _engines[clientId];

  /// App returned to the foreground: reconnect any idle WebSockets.
  void resumeAll() {
    for (final engine in _engines.values) {
      engine.resume();
    }
  }

  void _emit(int clientId, Map<String, dynamic> event) {
    final normalized = qlNormalizeJson(event) as Map<String, dynamic>;
    normalized['@client_id'] = clientId;
    // Always deliver asynchronously so TdClient never re-enters itself from
    // inside a send() call.
    scheduleMicrotask(() {
      final listener = _listener;
      if (listener != null) {
        listener(normalized);
      } else {
        _queue.add(normalized);
      }
    });
  }

  void send(int clientId, String request) {
    final Object? decoded;
    try {
      decoded = jsonDecode(request);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final extra = decoded['@extra'];
    final engine = _engines[clientId];
    if (engine == null) {
      if (extra != null) {
        _emit(clientId, {
          '@type': 'error',
          'code': 400,
          'message': 'Invalid client',
          '@extra': extra,
        });
      }
      return;
    }
    unawaited(
      engine.handle(decoded).then((result) {
        if (extra == null) return;
        final response = Map<String, dynamic>.of(result);
        response['@extra'] = extra;
        _emit(clientId, response);
      }),
    );
  }

  String? receive(double timeout) {
    if (_queue.isEmpty) return null;
    return jsonEncode(_queue.removeFirst());
  }

  Object? receiveJson(double timeout) {
    if (_queue.isEmpty) return null;
    return _queue.removeFirst();
  }

  String? execute(String request) {
    final Object? decoded;
    try {
      decoded = jsonDecode(request);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return jsonEncode(QlTdEngine.executeSync(decoded));
  }

  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) {
    final source = File(sourcePath);
    final dir = source.parent;
    final sessionFile = File('${dir.path}/qingliao_session.json');
    if (!sessionFile.existsSync()) {
      throw StateError('No 轻聊 session found to export');
    }
    final raw = jsonDecode(sessionFile.readAsStringSync());
    if (raw is! Map) {
      throw StateError('轻聊 session file is invalid');
    }
    final payload = utf8.encode(jsonEncode({
      'v': 1,
      'server': raw['server'],
      'token': raw['token'],
      'user_id': raw['user_id'],
      'handle': raw['handle'],
      'device_id': raw['device_id'],
    }));
    if (payload.length > 247) {
      throw StateError('轻聊 session is too large to pack');
    }
    final authKey = Uint8List(256);
    final magic = utf8.encode('QLSESS01');
    authKey.setAll(0, magic);
    authKey[8] = payload.length;
    authKey.setAll(9, payload);
    return TdSessionString.encode(
      TdSessionStringData(
        dcId: 1,
        apiId: apiId,
        testMode: testMode,
        authKey: authKey,
        userId: userId,
        isBot: false,
      ),
    );
  }

  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}

  void importSessionString(String sessionString, String destinationPath) {
    final data = TdSessionString.decode(sessionString);
    final key = data.authKey;
    final magic = utf8.encode('QLSESS01');
    var magicOk = key.length >= 8;
    for (var i = 0; magicOk && i < magic.length; i++) {
      if (key[i] != magic[i]) magicOk = false;
    }
    if (!magicOk) {
      throw const FormatException('Not a 轻聊 session string');
    }
    final n = key[8];
    if (n <= 0 || 9 + n > key.length) {
      throw const FormatException('轻聊 session string is truncated');
    }
    final raw = jsonDecode(utf8.decode(key.sublist(9, 9 + n)));
    if (raw is! Map || (raw['token']?.toString() ?? '').isEmpty || (raw['user_id']?.toString() ?? '').isEmpty) {
      throw const FormatException('轻聊 session string is missing fields');
    }
    final dest = File(destinationPath);
    dest.parent.createSync(recursive: true);
    File('${dest.parent.path}/qingliao_session.json').writeAsStringSync(jsonEncode({
      'server': raw['server'] ?? '',
      'token': raw['token'],
      'user_id': raw['user_id'],
      'handle': raw['handle'] ?? '',
      'device_id': raw['device_id'] ?? '',
      'event_cursor': 0,
    }), flush: true);
    dest.writeAsBytesSync(utf8.encode('QLSESS01'), flush: true);
  }
}
