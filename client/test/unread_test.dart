import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;

class HistoryEngine extends ChatEngine {
  HistoryEngine(super.store, super.vault);
  @override
  Future<void> loadHistory(String cid, {int? before}) async {}
  @override
  Future<void> loadMembers(String cid) async {}
  @override
  Future<void> loadPins(String cid) async {}
  @override
  void retryPending() {}
  @override
  Future<String> send(
    String cid,
    String text, {
    String kind = 'text',
    String mediaId = '',
    String replyTo = '',
    List<Json> entities = const [],
  }) async {
    final id = 'local-${messages.length + 1}';
    messages[id] = {
      'id': id,
      'client_msg_id': id,
      'conversation_id': cid,
      'conversation_seq': messages.length + 1,
      'sender_id': uid,
      'kind': kind,
      'text': text,
      'media_id': mediaId,
      'reply_to': replyTo,
      'entities': entities,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'deleted': false,
      'status': 'stored',
    };
    notifyListeners();
    return id;
  }

  @override
  Future<void> read(String cid, int seq) async {
    if (number(dialogs[cid]?['last_read_seq']) >= seq) return;
    dialogs[cid]!['last_read_seq'] = seq;
    dialogs[cid]!['unread_count'] = 0;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'open at first unread, retain session divider, bottom button clears count and next open has no divider',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final engine = HistoryEngine(store, MemoryVault());
      engine.session = {'user_id': 'me'};
      engine.online = true;
      engine.dialogs['chat'] = {
        'id': 'chat',
        'kind': 'direct',
        'last_read_seq': 10,
        'unread_count': 30,
      };
      for (var i = 1; i <= 40; i++) {
        engine.messages['m$i'] = {
          'id': 'm$i',
          'conversation_id': 'chat',
          'sender_id': 'peer',
          'kind': 'text',
          'text': '消息 $i',
          'conversation_seq': i,
          'created_at': '2026-11-10T16:04:00Z',
        };
      }
      Future<void> page(int key) => tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            key: ValueKey(key),
            engine: engine,
            cid: 'chat',
            title: '测试用户',
          ),
        ),
      );
      await page(1);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('unread-divider')), findsOneWidget);
      expect(find.text('消息 11', findRichText: true), findsOneWidget);
      expect(find.byTooltip('有未读消息'), findsOneWidget);
      expect(number(engine.dialogs['chat']!['last_read_seq']), 10);
      await tester.tap(find.byTooltip('有未读消息'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(number(engine.dialogs['chat']!['last_read_seq']), 40);
      await page(2);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('unread-divider')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await engine.shutdown();
      await tester.runAsync(store.close);
    },
  );
}
