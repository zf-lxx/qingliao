//
//  app_press_ripple_test.dart
//
//  Opening a chat often happens before the row sees pointer-up, so the press
//  ripple would freeze mid-expansion. The list is also snapshotted for the
//  enter/exit transition; the stain must already be gone before that texture
//  is taken, and must stay gone after the chat is popped.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/app/app_navigator.dart';
import 'package:qingliao/components/app_press_ripple.dart';

void main() {
  setUp(ChatShellCover.debugReset);
  tearDown(ChatShellCover.debugReset);

  testWidgets(
    'a mid-press ripple is gone after a chat route is pushed without pointer-up',
    (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: SnapshotWidget(
            controller: chatShellSnapshotController,
            mode: SnapshotMode.permissive,
            child: const Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: AppPressRipple(
                  child: ColoredBox(color: Color(0xFF111111)),
                ),
              ),
            ),
          ),
        ),
      );

      final row = tester.getRect(find.byType(AppPressRipple));
      // Press the right half, where the time and tick sit on a chat row.
      final gesture = await tester.startGesture(
        Offset(row.right - 24, row.center.dy),
      );
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsOneWidget);

      final pushed = navKey.currentState!.push<void>(
        AppChatPageRoute<void>(
          builder: (_) => const SizedBox(key: ValueKey('chat')),
        ),
      );
      await tester.pump();
      expect(chatShellSnapshotController.allowSnapshotting, isTrue);
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat')), findsOneWidget);
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      navKey.currentState!.pop();
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      await tester.pumpAndSettle();
      await pushed;
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);
    },
  );

  testWidgets(
    'ChatShellCover.acquire drops a mid-press ripple before snapshotting',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SnapshotWidget(
            controller: chatShellSnapshotController,
            mode: SnapshotMode.permissive,
            child: const SizedBox(
              height: 72,
              width: 400,
              child: AppPressRipple(
                child: ColoredBox(color: Color(0xFF111111)),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPressRipple)),
      );
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsOneWidget);

      ChatShellCover.acquire();
      await tester.pump();
      expect(chatShellSnapshotController.allowSnapshotting, isTrue);
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      ChatShellCover.release();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);
    },
  );
}
