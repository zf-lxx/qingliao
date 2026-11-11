import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/ui/motion/tg_motion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

void main() {
  testWidgets('press, release, cancel retain feedback and callback semantics', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 80, child: Text('按钮')),
            ),
          ),
        ),
      ),
    );
    final down = await tester.startGesture(tester.getCenter(find.text('按钮')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(PressableScale),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.storage[0], lessThan(1));
    await down.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    final cancel = await tester.startGesture(tester.getCenter(find.text('按钮')));
    await cancel.cancel();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
  testWidgets(
    'edge back follows finger, can cancel, and velocity finish pops',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    TgPageRoute(
                      page: const Scaffold(body: Center(child: Text('第二页'))),
                    ),
                  ),
                  child: const Text('进入'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入'));
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('进入'), findsOneWidget);
      await tester.pump();
      final origin = tester.getTopLeft(find.text('第二页')).dx;
      final startPx = (0.4 / 2.54) * tester.view.devicePixelRatio * 160;
      final drag = await tester.startGesture(const Offset(10, 200));
      await drag.moveBy(Offset(startPx * 0.4, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('第二页')).dx, origin);
      await drag.moveBy(Offset(startPx + 80, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('第二页')).dx, greaterThan(origin + 30));
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
      final fling = await tester.startGesture(const Offset(10, 200));
      await fling.moveBy(Offset(startPx + 20, 0));
      await tester.pump();
      await fling.moveBy(
        const Offset(500, 0),
        timeStamp: const Duration(milliseconds: 80),
      );
      await fling.up();
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsNothing);
      expect(find.text('进入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('home list stays alive behind chat and restores scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final engine = HistoryEngine(store, MemoryVault());
    engine.session = {'user_id': 'me', 'server': 'http://127.0.0.1'};
    engine.online = true;
    for (var i = 0; i < 20; i++) {
      engine.dialogs['d$i'] = {
        'id': 'd$i',
        'kind': 'direct',
        'display_title': '会话$i',
        'last_activity': 20 - i,
        'unread_count': 0,
        'last_message': {
          'text': '预览$i',
          'kind': 'text',
          'sender_id': 'peer',
          'created_at': '2026-11-10T15:00:00Z',
        },
      };
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DialogsPage(engine: engine),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('会话0'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('会话0'), findsNothing);
    await tester.tap(find.text('会话8').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('会话8'), findsWidgets);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(DialogsPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    expect(find.text('会话0'), findsNothing);
    expect(engine.scrollOffsets[ChatEngine.homeScrollKey], greaterThan(100));
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.shutdown();
    await tester.runAsync(store.close);
  });
}
