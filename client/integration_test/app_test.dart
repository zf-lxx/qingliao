import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/core/api.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: UI login, real dual-account text, offline retry + sync and screenshots',
    (tester) async {
      const base = String.fromEnvironment('TEST_SERVER');
      const password = String.fromEnvironment('TEST_PASSWORD');
      expect(
        base.isNotEmpty && password.isNotEmpty,
        true,
        reason:
            'Run scripts/android_acceptance.py, never embed real credentials',
      );
      final anon = ChatApi(base);
      final adminLogin = obj(
        await anon.call('POST', '/auth/login', {
          'handle': 'admin',
          'password': password,
        }),
      );
      final admin = ChatApi(base, token: adminLogin['access_token']);
      final invitation = obj(
        await admin.call('POST', '/invites', {'uses': 2, 'expires_hours': 1}),
      );
      final a = obj(
        await anon.call('POST', '/auth/register', {
          'handle': 'xiaxia',
          'password': password,
          'invite_code': invitation['invite_code'],
          'display_name': '小夏',
        }),
      );
      final b = obj(
        await anon.call('POST', '/auth/register', {
          'handle': 'ache',
          'password': password,
          'invite_code': invitation['invite_code'],
          'display_name': '阿澈',
        }),
      );
      final peer = ChatApi(base, token: b['access_token']);
      final owner = ChatApi(base, token: a['access_token']);
      final cid =
          (await owner.call('POST', '/conversations', {
                'kind': 'direct',
                'member_ids': [b['user_id']],
              }))['id']
              as String;
      final group =
          (await owner.call('POST', '/conversations', {
                'kind': 'group',
                'title': '轻聊 · 内测小组',
                'member_ids': [b['user_id']],
              }))['id']
              as String;
      await owner.call('POST', '/conversations/$cid/messages', {
        'kind': 'text',
        'text': '终于可以在自己的服务器上聊天了。',
        'client_msg_id': 'seed-1',
      });
      await peer.call('POST', '/conversations/$cid/messages', {
        'kind': 'text',
        'text': '你好，小夏。消息已经实时抵达 ✨',
        'client_msg_id': 'seed-2',
      });
      await peer.call('POST', '/conversations/$group/messages', {
        'kind': 'text',
        'text': '@xiaxia 来测一下群聊和未读提醒吧。',
        'client_msg_id': 'seed-3',
      });
      await owner.call('PATCH', '/conversations/$group/state', {
        'pinned_order': 1,
        'mute_until': 'forever',
        'draft': {'text': '今晚继续测试', 'entities': []},
      });
      final store = await LocalStore.open(
        path: 'acceptance-${DateTime.now().millisecondsSinceEpoch}.db',
      );
      final vault = SecureSessionVault();
      await vault.clear();
      final engine = ChatEngine(store, vault);
      await tester.pumpWidget(QingliaoApp(engine: engine));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('01-login');
      Future<void> waitFor(bool Function() condition, String reason) async {
        for (var i = 0; i < 160; i++) {
          if (condition()) return;
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Timed out: $reason');
      }

      final frames = <Json>[];
      final ws = peer.socket();
      await ws.ready;
      final sub = ws.stream.listen((raw) {
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
      await tester.enterText(find.byKey(const Key('server')), base);
      await tester.enterText(find.byKey(const Key('handle')), 'xiaxia');
      await tester.enterText(find.byKey(const Key('password')), password);
      await tester.tap(find.byKey(const Key('login')));
      await waitFor(
        () => engine.online && engine.dialogs.length == 2,
        'login and dialogs',
      );
      await waitFor(
        () => find.text('阿澈').evaluate().isNotEmpty,
        'resolved real profile name',
      );
      expect((await vault.read())?['device_id'], engine.session?['device_id']);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('02-dialogs');
      await tester.tap(find.text('阿澈').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('composer')),
        '从 Android 界面发出的第一条消息',
      );
      await tester.tap(find.byKey(const Key('send')));
      await waitFor(
        () =>
            frames.any((f) => obj(f['data'])['text'] == '从 Android 界面发出的第一条消息'),
        'UI send reaches peer WebSocket',
      );
      ws.sink.add(
        jsonEncode({
          'v': 1,
          'op': 'message.send',
          'req_id': 'peer-live',
          'conversation_id': cid,
          'client_msg_id': 'android-peer-live',
          'payload': {
            'kind': 'text',
            'text': '收到了！双向 WebSocket 已接通。',
            'entities': [
              {'type': 'bold', 'offset': 4, 'length': 11},
            ],
          },
        }),
      );
      await waitFor(
        () => engine.messages['android-peer-live'] != null,
        'peer text rendered in app',
      );
      await engine.disconnect();
      await peer.call('POST', '/conversations/$cid/messages', {
        'kind': 'text',
        'text': '你离线时，我也发来了一条消息。',
        'client_msg_id': 'android-offline-in',
      });
      await tester.enterText(find.byKey(const Key('composer')), '离线发送，重连后自动补发');
      await tester.tap(find.byKey(const Key('send')));
      await waitFor(
        () => engine.outbox.length == 1,
        'durable UI offline outbox',
      );
      final stable = engine.outbox.keys.single;
      await engine.resume();
      await waitFor(
        () =>
            engine.online &&
            engine.outbox.isEmpty &&
            engine.messages['android-offline-in'] != null,
        'Android reconnect sync and retry',
      );
      final backend = objects(
        (await peer.call('GET', '/conversations/$cid/messages'))['messages'],
      );
      expect(backend.where((m) => m['client_msg_id'] == stable).length, 1);
      await engine.loadMembers(cid);
      final sent = engine.messages[stable]!;
      await engine.pin(sent);
      await engine.react(sent, '👍');
      await engine.loadPins(cid);
      await engine.loadReactions(sent['id']);
      await tester.pumpAndSettle();
      // Dismiss any software keyboard before taking actual Android screenshots.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03-chat');
      final text = find.text('离线发送，重连后自动补发', findRichText: true);
      await tester.longPress(text.last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('04-reactions-menu');
      expect(find.text('回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(15, 80));
      await tester.pumpAndSettle();
      await engine.logout();
      await engine.shutdown();
      await store.close();
      await sub.cancel();
      await ws.sink.close();
      admin.close();
      anon.close();
      peer.close();
      owner.close();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
