import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/api.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault, eventually;

void main() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  HttpOverrides.global = null;
  testWidgets(
    'real UI: composer tap -> peer WS, incoming bubble, offline UI outbox -> reconnect',
    (tester) async {
      tester.view.physicalSize = const Size(432, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final font in [
        ('ChatSans', 'assets/fonts/ChatSans.otf'),
        ('ChatEmoji', 'assets/fonts/ChatEmoji.ttf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
      }
      final dir = await Directory.systemTemp.createTemp('qingliao-live-ui-');
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
      expect(build.exitCode, 0);
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
      ChatEngine? engine;
      LocalStore? store;
      StreamSubscription? sub;
      ChatApi? peer, admin;
      try {
        for (var i = 0; i < 100; i++) {
          try {
            final s = await Socket.connect('127.0.0.1', port);
            s.destroy();
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        final base = 'http://127.0.0.1:$port',
            anon = ChatApi('http://127.0.0.1:$port');
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
        sqfliteFfiInit();
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/ui.db',
        );
        engine = ChatEngine(store, MemoryVault());
        await engine.authenticate(
          base,
          'xiaxia',
          password,
          invite: invite['invite_code'],
          name: '小夏',
        );
        await eventually(() => engine!.online);
        final b = obj(
          await anon.call('POST', '/auth/register', {
            'handle': 'ache',
            'password': password,
            'invite_code': invite['invite_code'],
            'display_name': '阿澈',
          }),
        );
        peer = ChatApi(base, token: b['access_token']);
        anon.close();
        final cid =
            (await engine.api!.call('POST', '/conversations', {
                  'kind': 'direct',
                  'member_ids': [b['user_id']],
                }))['id']
                as String;
        await engine.refreshDialogs();
        await engine.title(engine.dialogs[cid]!);
        final frames = <Json>[], ws = peer.socket();
        await ws.ready;
        sub = ws.stream.listen((raw) {
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
        const key = Key('live-shot');
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: QingliaoApp(engine: engine),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('阿澈').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('composer')),
          '从真实界面的发送按钮出发。',
        );
        await tester.tap(find.byKey(const Key('send')));
        await eventually(
          () => frames.any((f) => obj(f['data'])['text'] == '从真实界面的发送按钮出发。'),
          reason: 'UI send reaches peer WS',
        );
        ws.sink.add(
          jsonEncode({
            'v': 1,
            'op': 'message.send',
            'req_id': 'reply',
            'conversation_id': cid,
            'client_msg_id': 'live-ui-reply',
            'payload': {'kind': 'text', 'text': '收到！你的消息已经到达第二个账号 ✨'},
          }),
        );
        await eventually(() => engine!.messages['live-ui-reply'] != null);
        await tester.pumpAndSettle();
        expect(
          find.text('收到！你的消息已经到达第二个账号 ✨', findRichText: true),
          findsOneWidget,
        );
        await engine.disconnect();
        await peer.call('POST', '/conversations/$cid/messages', {
          'kind': 'text',
          'text': '离线时也没有漏掉我。',
          'client_msg_id': 'live-ui-offline-in',
        });
        await tester.enterText(
          find.byKey(const Key('composer')),
          '离线发出，重连补发，UUID 不变。',
        );
        await tester.tap(find.byKey(const Key('send')));
        await eventually(() => engine!.outbox.length == 1);
        final stable = engine.outbox.keys.single;
        await engine.resume();
        await eventually(
          () =>
              engine!.online &&
              engine.outbox.isEmpty &&
              engine.messages['live-ui-offline-in'] != null,
        );
        await tester.pumpAndSettle();
        expect(find.text('离线时也没有漏掉我。', findRichText: true), findsOneWidget);
        final messages = objects(
          (await peer.call('GET', '/conversations/$cid/messages'))['messages'],
        );
        expect(messages.where((m) => m['client_msg_id'] == stable).length, 1);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('shots').create(recursive: true);
        await File('shots/05-chat-live-desktop.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await ws.sink.close();
        await sub.cancel();
        sub = null;
      } finally {
        await sub?.cancel();
        await engine?.shutdown();
        await store?.close();
        peer?.close();
        admin?.close();
        server.kill(ProcessSignal.sigterm);
        await server.exitCode.timeout(const Duration(seconds: 10));
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
