import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/ui/chat/chat_widgets.dart';
import 'package:qingliao/ui/home/chat_list_widgets.dart';
import 'package:qingliao/ui/motion/tg_motion.dart';
import 'package:qingliao/ui/profile/chat_info_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

class MenuEngine extends HistoryEngine {
  MenuEngine(super.store, super.vault);
  @override
  Future<void> loadReactions(String mid) async {}
}

void main() {
  testWidgets(
    'message menu enters multi-select, toggles rows and back cancels selection',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final engine = MenuEngine(store, MemoryVault())
        ..session = {'user_id': 'me'}
        ..online = true;
      engine.dialogs['chat'] = {'id': 'chat', 'kind': 'direct'};
      for (var i = 1; i <= 3; i++) {
        engine.messages['m$i'] = {
          'id': 'm$i',
          'conversation_id': 'chat',
          'conversation_seq': i,
          'sender_id': 'peer',
          'kind': 'text',
          'text': '测试消息$i',
          'created_at': '2026-11-10T16:00:00Z',
        };
      }
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(engine: engine, cid: 'chat', title: '测试聊天'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('测试消息1', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('选择'), findsOneWidget);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(
        tester
            .widgetList<TgSelectableMessage>(find.byType(TgSelectableMessage))
            .where((w) => w.selected)
            .length,
        1,
      );
      await tester.tapAt(
        tester.getCenter(find.text('测试消息2', findRichText: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选择 2 项'), findsOneWidget);
      expect(
        find.byTooltip('撤回所选'),
        findsNothing,
      ); // Cannot revoke somebody else's private messages.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('已选择 2 项'), findsNothing);
      expect(find.byKey(const Key('composer')), findsOneWidget);
      await tester.tap(find.text('测试聊天').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoPage), findsOneWidget);
      expect(find.text('媒体'), findsOneWidget);
      expect(find.textContaining('非全部历史统计'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await engine.shutdown();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'folder capsule moves between labels; large badge counts fit narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 'a';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, update) => TgFolderTabs(
                tabs: const [
                  (id: 'a', label: '全部', count: 1),
                  (id: 'b', label: '未读', count: 9999),
                ],
                selected: selected,
                onSelected: (id) => update(() => selected = id),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('未读'));
      await tester.pump(const Duration(milliseconds: 160));
      expect(selected, 'b');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('popup supports outside dismiss with reverse transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showTgPopup(
                context: c,
                builder: (c) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [ListTile(title: Text('菜单内容'))],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('菜单内容'), findsOneWidget);
    await tester.tapAt(const Offset(10, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('菜单内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
