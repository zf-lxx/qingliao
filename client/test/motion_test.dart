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
      final drag = await tester.startGesture(const Offset(10, 200));
      await drag.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('第二页')).dx, greaterThan(375));
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
      await tester.flingFrom(const Offset(10, 200), const Offset(500, 0), 1600);
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsNothing);
      expect(find.text('进入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
