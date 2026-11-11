import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/ui/motion/tg_motion.dart';
import 'package:qingliao/widgets/connection_title.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

void main() {
  for (final gesture in [false, true]) {
    testWidgets(
      'pop offsets are monotonic and background synced: gesture=$gesture',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            onGenerateRoute: (s) => TgPageRoute(
              settings: s,
              page: const Scaffold(body: SizedBox.expand(key: Key('list'))),
            ),
          ),
        );
        nav.currentState!.push(
          TgPageRoute(
            page: const Scaffold(body: SizedBox.expand(key: Key('chat'))),
          ),
        );
        await tester.pumpAndSettle();
        if (gesture) {
          final drag = await tester.startGesture(const Offset(8, 200));
          await drag.moveBy(const Offset(450, 0));
          await tester.pump();
          await drag.up();
        } else {
          nav.currentState!.pop();
        }
        double previous = -1, previousBackground = -10000;
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          if (find.byKey(const Key('chat')).evaluate().isEmpty) break;
          final x = tester.getTopLeft(find.byKey(const Key('chat'))).dx;
          final back = tester.getTopLeft(find.byKey(const Key('list'))).dx;
          expect(x, greaterThanOrEqualTo(previous - .01));
          expect(back, greaterThanOrEqualTo(previousBackground - .01));
          expect(back, closeTo(-.25 * (800 - x), .01));
          previous = x;
          previousBackground = back;
        }
        await tester.pumpAndSettle();
        expect(nav.currentState!.userGestureInProgress, isFalse);
        expect(find.byKey(const Key('chat')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'full-width swipe clears gesture flag; large Android text is clamped',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.qingliao.app/network'),
            (_) async => null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('xyz.qingliao.app/network'),
              null,
            ),
      );
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
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(QingliaoApp(engine: e));
      await tester.pump(const Duration(milliseconds: 400));
      final context = tester.element(find.byType(DialogsPage));
      expect(MediaQuery.textScalerOf(context).scale(16), closeTo(18.4, .001));
      final title = tester.widget<ConnectionTitle>(
        find.byType(ConnectionTitle),
      );
      expect(title.style?.fontSize, 20);
      final nav = Navigator.of(context);
      nav.push(
        TgPageRoute(
          page: const Scaffold(body: SizedBox.expand(key: Key('full'))),
        ),
      );
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(const Offset(8, 200));
      await drag.moveBy(const Offset(1000, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(nav.userGestureInProgress, isFalse);
      expect(find.byKey(const Key('full')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await e.shutdown();
      await tester.runAsync(store.close);
    },
  );
}
