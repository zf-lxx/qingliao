import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/widgets/connection_title.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;

class IndicatorEngine extends ChatEngine {
  IndicatorEngine(super.store, super.vault);
  void status({required bool connected, bool updating = false}) {
    online = connected;
    syncing = updating;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'title delays 1s, stays left, animates in-place and removes itself after reconnect',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final engine = IndicatorEngine(store, MemoryVault());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              title: ConnectionTitle(engine: engine, title: '轻聊'),
            ),
            body: const Text('会话列表', key: Key('body')),
          ),
        ),
      );
      final bodyY = tester.getTopLeft(find.byKey(const Key('body'))).dy;
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text('连接中'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('连接中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getTopLeft(find.text('连接中')).dx, lessThan(100));
      expect(tester.getTopLeft(find.byKey(const Key('body'))).dy, bodyY);
      engine.status(connected: true, updating: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('更新中'), findsOneWidget);
      engine.status(connected: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('轻聊'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // A quick network switch must not flash the indicator.
      engine.status(connected: false);
      await tester.pump(const Duration(milliseconds: 500));
      engine.status(connected: true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('连接中'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await engine.shutdown();
      await tester.runAsync(store.close);
    },
  );
}
