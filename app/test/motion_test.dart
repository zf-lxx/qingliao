import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/app/app_navigator.dart';
import 'package:qingliao/chat/message_swipe_reply.dart';
import 'package:qingliao/render/ql_curves.dart';

void main() {
  setUp(ChatShellCover.debugReset);
  tearDown(ChatShellCover.debugReset);

  test(
    'an unopened chat route is translucent so the list can show in the gap',
    () {
      final route = AppChatPageRoute<void>(builder: (_) => const SizedBox());
      expect(route.opaque, isFalse);
      expect(route.barrierColor, isNull);
      expect(route.maintainState, isTrue);
    },
  );

  testWidgets(
    'a settled chat route covers the list; enter and exit stay translucent',
    (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const SizedBox(key: ValueKey('list')),
        ),
      );
      final route = AppChatPageRoute<void>(
        builder: (_) => const SizedBox(key: ValueKey('chat')),
      );
      final pushed = navKey.currentState!.push(route);
      await tester.pump();
      expect(route.opaque, isFalse);
      expect(ChatShellCover.debugCoverCount, 1);
      expect(chatShellSnapshotController.allowSnapshotting, isTrue);
      expect(find.byType(ScaleTransition), findsNothing);

      await tester.pumpAndSettle();
      expect(route.opaque, isTrue);
      expect(find.byKey(const ValueKey('chat')), findsOneWidget);

      navKey.currentState!.pop();
      await tester.pump();
      expect(route.opaque, isFalse);
      expect(find.byType(ScaleTransition), findsNothing);

      await tester.pumpAndSettle();
      await pushed;
      expect(ChatShellCover.debugCoverCount, 0);
      expect(chatShellSnapshotController.allowSnapshotting, isFalse);
    },
  );

  test(
    'swipe-to-reply clamp, trigger and snap follow the documented values',
    () {
      expect(messageSwipeReplyTrigger, 96);
      expect(messageSwipeReplyHardLimit, 120);
      expect(messageSwipeReplyOffset(-120), -120);
      expect(messageSwipeReplyOffset(-200), -120);
      expect(messageSwipeReplyOffset(20), 0);
      expect(messageSwipeReplyCommits(offset: -96), isTrue);
      expect(messageSwipeReplyCommits(offset: -20), isFalse);
      expect(QlDuration.swipeSnap, const Duration(milliseconds: 180));
    },
  );

  testWidgets('swipe-reply start threshold uses 1.2cm in logical pixels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2, size: Size(400, 800)),
        child: SizedBox(),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    expect(
      messageSwipeReplyStartPx(context),
      closeTo(messageSwipeReplyStartDistance(), 0.0001),
    );
    expect(
      messageSwipeReplyStartPx(context),
      closeTo((1.2 / 2.54) * 160, 0.0001),
    );
  });
}
