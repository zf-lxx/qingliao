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

import '../qingliao/ql_engine.dart';

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

  bool get supportsSessionStringBackup => false;
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
    throw UnsupportedError('Session strings are not supported by 轻聊');
  }

  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}

  void importSessionString(String sessionString, String destinationPath) {
    throw UnsupportedError('Session strings are not supported by 轻聊');
  }
}
