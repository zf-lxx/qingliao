import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qingliao/core/api.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart' show compressImage;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MemoryVault implements SessionVault {
  Json? value;
  @override
  Future<Json?> read() async => value;
  @override
  Future<void> write(Json session) async {
    value = Map.from(session);
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

Future<void> eventually(
  bool Function() predicate, {
  String reason = 'condition',
  int seconds = 15,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('real Go server: WS exchange, durable cursor/outbox, reconnect, idempotency, edit, recall, media, privacy', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('qingliao-client-live-');
    final bind = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = bind.port;
    await bind.close();
    final password =
        'T${List.generate(24, (_) => Random.secure().nextInt(10)).join()}';
    final secret = File('${dir.path}/bootstrap');
    await secret.writeAsString(password);
    await Process.run('chmod', ['600', secret.path]);
    final build = await Process.run('go', [
      'build',
      '-o',
      '${dir.path}/server',
      './cmd/server',
    ], workingDirectory: '../server');
    expect(build.exitCode, 0, reason: build.stderr.toString());
    final server = await Process.start(
      '${dir.path}/server',
      [],
      environment: {
        'CHAT_ADDR': '127.0.0.1:$port',
        'CHAT_DATA': '${dir.path}/data',
        'CHAT_ADMIN_HANDLE': 'admin',
        'CHAT_ADMIN_PASSWORD_FILE': secret.path,
      },
    );
    server.stdout.drain<void>();
    server.stderr.drain<void>();
    ChatEngine? a;
    LocalStore? store;
    ChatApi? admin, b;
    StreamSubscription? peerSub;
    try {
      final base = 'http://127.0.0.1:$port';
      for (var i = 0; i < 100; i++) {
        try {
          final s = await Socket.connect('127.0.0.1', port);
          s.destroy();
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      final anon = ChatApi(base);
      final login = obj(
        await anon.call('POST', '/auth/login', {
          'handle': 'admin',
          'password': password,
        }),
      );
      admin = ChatApi(base, token: login['access_token']);
      final invite = obj(
        await admin.call('POST', '/invites', {'uses': 2, 'expires_hours': 1}),
      );
      store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/client.db',
      );
      final vault = MemoryVault();
      a = ChatEngine(store, vault);
      await a.authenticate(
        base,
        'alice',
        password,
        invite: invite['invite_code'],
        name: '小夏',
      );
      await eventually(() => a!.online, reason: 'app connected');
      final bSession = obj(
        await anon.call('POST', '/auth/register', {
          'handle': 'bravo',
          'password': password,
          'invite_code': invite['invite_code'],
          'display_name': '阿澈',
        }),
      );
      b = ChatApi(base, token: bSession['access_token']);
      anon.close();
      final cid =
          (await a.api!.call('POST', '/conversations', {
                'kind': 'direct',
                'member_ids': [bSession['user_id']],
              }))['id']
              as String;
      await a.refreshDialogs();
      expect(await a.title(a.dialogs[cid]!), '阿澈');
      final frames = <Json>[];
      final ws = b.socket();
      await ws.ready;
      peerSub = ws.stream.listen((raw) {
        final f = obj(jsonDecode(raw as String));
        frames.add(f);
        if (f['op'] == 'hello') {
          ws.sink.add(
            jsonEncode({
              'v': 1,
              'op': 'sync.resume',
              'req_id': 'resume',
              'after_event_seq': 0,
            }),
          );
        }
      });
      await a.send(
        cid,
        '客户端 → 第二账号 😀',
        entities: [
          {'type': 'bold', 'offset': 0, 'length': 3},
        ],
      );
      await eventually(
        () =>
            a!.outbox.isEmpty &&
            frames.any((f) => obj(f['data'])['text'] == '客户端 → 第二账号 😀'),
        reason: 'app text reaches second WebSocket',
      );
      ws.sink.add(
        jsonEncode({
          'v': 1,
          'op': 'message.send',
          'req_id': 'peer-send',
          'conversation_id': cid,
          'client_msg_id': 'peer-live-1',
          'payload': {'kind': 'text', 'text': '第二账号 → 客户端'},
        }),
      );
      await eventually(
        () => a!.history(cid).any((m) => m['client_msg_id'] == 'peer-live-1'),
        reason: 'second WebSocket reaches app',
      );
      await a.disconnect();
      final savedCursor = a.cursor;
      await b.call('POST', '/conversations/$cid/messages', {
        'client_msg_id': 'peer-offline-1',
        'kind': 'text',
        'text': '离线期间的消息',
      });
      await a.draft(cid, '离线草稿也会恢复', '');
      await a.send(cid, '离线发件箱消息');
      final stableId = a.outbox.keys.single;
      final durable = await store.load(a.account);
      expect(obj(durable['outbox']).containsKey(stableId), true);
      expect(number(durable['cursor']), savedCursor);
      // Process restart before transmission: no in-memory transport can rescue us.
      await a.shutdown();
      a = ChatEngine(store, vault);
      await a.boot();
      await eventually(
        () =>
            a!.online &&
            a.outbox.isEmpty &&
            a.history(cid).any((m) => m['client_msg_id'] == 'peer-offline-1'),
        reason: 'restart + offline sync + outbox flush',
      );
      expect(a.cursor, greaterThan(savedCursor));
      await eventually(
        () => a!.draftOutbox.isEmpty,
        reason: 'offline draft queue flush',
      );
      final ownerDialogs = objects(
        (await a.api!.call(
          'GET',
          '/conversations?archived=all',
        ))['conversations'],
      );
      expect(
        obj(ownerDialogs.singleWhere((d) => d['id'] == cid)['draft'])['text'],
        '离线草稿也会恢复',
      );
      final sent = a.messages[stableId]!;
      expect(sent['status'], 'stored');
      // Simulate ACK loss: enqueue exact original payload with SAME client UUID.
      a.outbox[stableId] = {...sent, 'status': 'pending'};
      await a.persist();
      a.retryPending();
      await eventually(() => a!.outbox.isEmpty, reason: 'idempotent retry ACK');
      final backend = objects(
        (await b.call('GET', '/conversations/$cid/messages'))['messages'],
      );
      expect(backend.where((m) => m['client_msg_id'] == stableId).length, 1);
      await a.edit(sent, '编辑后的正文');
      await eventually(() => a!.messages[stableId]?['text'] == '编辑后的正文');
      await a.react(sent, '👍');
      await a.loadReactions(sent['id']);
      expect(a.reactions[sent['id']]!.any((r) => r['emoji'] == '👍'), true);
      await a.pin(sent);
      await a.loadPins(cid);
      expect(a.pins[cid]!.any((m) => m['id'] == sent['id']), true);
      await a.state(cid, {
        'pinned_order': 1,
        'mute_until': 'forever',
        'draft': {'text': '跨端草稿', 'entities': []},
      });
      await eventually(
        () =>
            a!.dialogs[cid]?['pinned_order'] == 1 &&
            obj(a.dialogs[cid]?['draft'])['text'] == '跨端草稿',
      );
      final group =
          (await a.api!.call('POST', '/conversations', {
                'kind': 'group',
                'title': '轻聊 · 内测小组',
                'member_ids': [bSession['user_id']],
              }))['id']
              as String;
      await b.call('POST', '/conversations/$group/messages', {
        'client_msg_id': 'group-mention',
        'kind': 'text',
        'text': '@alice 群聊与提及已经接通。',
      });
      await a.state(group, {
        'pinned_order': 2,
        'mute_until': 'forever',
        'draft': {'text': '今晚继续测试', 'entities': []},
      });
      await a.refreshDialogs();
      await a.title(a.dialogs[cid]!);
      await a.loadMembers(cid);
      // Data-only fixture is from this real Go session. No password/token.
      await Directory('artifacts').create(recursive: true);
      await File('artifacts/screens-state.json').writeAsString(
        jsonEncode({
          'state': a.snapshot(),
          'user_id': a.uid,
          'privacy': a.privacy,
          'users': a.users,
          'pins': a.pins,
          'reactions': a.reactions,
        }),
      );
      // Image: same compression function as UI, authenticated raw upload and GET.
      final fixture = img.Image(width: 1800, height: 300);
      img.fill(fixture, color: img.ColorRgb8(70, 130, 180));
      final compressed = await compressImage(
        Uint8List.fromList(img.encodePng(fixture)),
      );
      expect(img.decodeJpg(compressed)!.width, 1600);
      expect(img.decodeJpg(compressed)!.exif.isEmpty, true);
      final media = await a.api!.upload(cid, compressed);
      await a.send(cid, '', kind: 'image', mediaId: media);
      await eventually(() => a!.outbox.isEmpty);
      expect((await b.media(media)).length, compressed.length);
      // Reciprocal privacy: server hides all reader positions when disabled.
      await a.api!.call('PUT', '/me/privacy', {'read_receipts_enabled': false});
      a.privacy = obj(await a.api!.call('GET', '/me/privacy'));
      await a.loadMembers(cid);
      expect(a.receipts, false);
      expect(a.isRead(sent), false);
      await a.recall(sent);
      await eventually(() => a!.messages[stableId]?['deleted'] == true);
      await a.loadPins(cid);
      expect(a.pins[cid], isEmpty);
      final oldAccount = a.account;
      await a.logout();
      expect(await vault.read(), isNull);
      expect(await store.load(oldAccount), isEmpty);
      expect(
        await store.load(
          '$base|${vault.value?['user_id'] ?? login['user_id']}',
        ),
        isA<Map>(),
      );
      await ws.sink.close();
    } finally {
      await peerSub?.cancel();
      await a?.shutdown();
      await store?.close();
      admin?.close();
      b?.close();
      server.kill(ProcessSignal.sigterm);
      await server.exitCode.timeout(const Duration(seconds: 10));
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
