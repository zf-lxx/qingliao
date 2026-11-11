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
      expect(find.byTooltip('回到最新消息'), findsOneWidget);
      expect(number(engine.dialogs['chat']!['last_read_seq']), 10);
      await tester.tap(find.byTooltip('回到最新消息'));
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
  testWidgets(
    'own-only history never anchors unread; variable-height rows converge to bottom',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final e = HistoryEngine(store, MemoryVault())
        ..session = {'user_id': 'me'}
        ..online = true;
      e.dialogs['chat'] = {
        'id': 'chat',
        'kind': 'direct',
        'last_read_seq': 0,
        'unread_count': 60,
      };
      for (var i = 1; i <= 80; i++) {
        e.messages['m$i'] = {
          'id': 'm$i',
          'conversation_id': 'chat',
          'sender_id': 'me',
          'kind': 'text',
          'text': i % 3 == 0 ? '长消息 $i\n' * 12 : '自己发送 $i',
          'conversation_seq': i,
          'created_at': '2026-11-10T16:04:00Z',
        };
      }
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(engine: e, cid: 'chat', title: '测试'),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('unread-divider')), findsNothing);
      final list = tester.widget<ListView>(find.byKey(const Key('messages')));
      expect(list.controller!.position.extentAfter, lessThan(1));
      expect(find.text('自己发送 80', findRichText: true), findsOneWidget);
      expect(number(e.dialogs['chat']!['last_read_seq']), 80);
      expect(
        imageHeight({
          'media_meta': {'width': 1000, 'height': 500},
        }),
        120,
      );
      expect(imageHeight({}), 180);
      await tester.drag(
        find.byKey(const Key('messages')),
        const Offset(0, 650),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final saved = e.viewPositions['chat']!;
      expect(saved['at_bottom'], false);
      final savedMessage = e.messages[saved['id']]!;
      final text = savedMessage['text'] as String;
      final originalY = tester
          .getTopLeft(find.text(text, findRichText: true).first)
          .dy;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(engine: e, cid: 'chat', title: '测试'),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        tester.getTopLeft(find.text(text, findRichText: true).first).dy,
        closeTo(originalY, 1),
      );
      expect(find.byKey(const Key('unread-divider')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await e.shutdown();
      await tester.runAsync(store.close);
    },
  );

  testWidgets('incoming unread anchor skips own and deleted messages', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final e = HistoryEngine(store, MemoryVault())
      ..session = {'user_id': 'me'}
      ..online = true;
    e.dialogs['chat'] = {
      'id': 'chat',
      'kind': 'direct',
      'last_read_seq': 1,
      'unread_count': 25,
    };
    for (var i = 1; i <= 50; i++) {
      e.messages['m$i'] = {
        'id': 'm$i',
        'conversation_id': 'chat',
        'sender_id': i < 10 ? 'me' : 'peer',
        'kind': 'text',
        'text': '消息 $i',
        'conversation_seq': i,
        'deleted': i == 10,
        'created_at': '2026-11-10T16:04:00Z',
      };
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(engine: e, cid: 'chat', title: '测试'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('unread-divider')), findsOneWidget);
    expect(find.text('消息 11', findRichText: true), findsOneWidget);
    final bar = tester.getTopLeft(find.byKey(const Key('unread-divider'))).dy;
    expect(
      tester.getTopLeft(find.text('消息 11', findRichText: true)).dy,
      greaterThan(bar),
    );
    await tester.pumpWidget(const SizedBox());
    await e.shutdown();
    await tester.runAsync(store.close);
  });
}
