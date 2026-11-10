import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/api.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault, eventually;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  for (final silentPhase in ['hello', 'resume']) {
    test(
      'half-open WS: $silentPhase deadline triggers automatic recovery',
      () async {
        sqfliteFfiInit();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        server.listen((r) async {
          if (r.uri.path == '/v1/ws') {
            final ws = await WebSocketTransformer.upgrade(r);
            sockets.add(ws);
            ws.listen((_) {});
            if (silentPhase == 'resume') {
              ws.add(jsonEncode({'v': 1, 'op': 'hello'}));
            }
            return;
          }
          final body = switch (r.uri.path) {
            '/v1/auth/login' => {
              'user_id': 'test',
              'access_token': 'fixture-token',
            },
            '/v1/conversations' => {'conversations': [], 'has_more': false},
            '/v1/folders' => {'folders': []},
            _ => <String, dynamic>{},
          };
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode(body));
          await r.response.close();
        });
        final store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        final engine = ChatEngine(
          store,
          MemoryVault(),
          handshakeTimeout: const Duration(milliseconds: 150),
        );
        try {
          await engine.authenticate(
            'http://127.0.0.1:${server.port}',
            'test',
            'fixture',
          );
          await eventually(
            () =>
                engine.lastConnectionFailure == '$silentPhase:TimeoutException',
            seconds: 3,
          );
          expect(engine.online, false);
          // No user tap required: a fresh socket is opened after the backoff.
          await eventually(() => sockets.length >= 2, seconds: 4);
        } finally {
          await engine.shutdown();
          await store.close();
          for (final ws in sockets) {
            await ws.close();
          }
          await server.close(force: true);
        }
      },
    );
  }
  test(
    'WS URI normalizes root slash, preserves port and never leaks token',
    () {
      final api = ChatApi('https://example.com:8443/', token: 'fixture-token');
      expect(api.socketUri.toString(), 'wss://example.com:8443/v1/ws');
      expect(api.headers['Authorization'], 'Bearer fixture-token');
      api.close();
    },
  );
}
