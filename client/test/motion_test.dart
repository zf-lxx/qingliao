import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/ui/motion/tg_motion.dart';

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
      await fling.moveBy(const Offset(500, 0), timeStamp: const Duration(milliseconds: 80));
      await fling.up();
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsNothing);
      expect(find.text('进入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
