import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/app/app_navigator.dart';
import 'package:qingliao/chat/message_swipe_reply.dart';
import 'package:qingliao/render/ql_curves.dart';

void main() {
  test('chat route stays translucent so the list can live behind it', () {
    final route = AppChatPageRoute<void>(builder: (_) => const SizedBox());
    expect(route.opaque, isFalse);
    expect(route.barrierColor, isNull);
    expect(route.maintainState, isTrue);
    expect(route.allowSnapshotting, isFalse);
  });

  test(
    'swipe-to-reply clamp, trigger and snap follow the documented values',
    () {
      expect(messageSwipeReplyTrigger, 50);
      expect(messageSwipeReplyHardLimit, 80);
      expect(messageSwipeReplyOffset(-80), -80);
      expect(messageSwipeReplyOffset(-200), -80);
      expect(messageSwipeReplyOffset(20), 0);
      expect(messageSwipeReplyCommits(offset: -50), isTrue);
      expect(messageSwipeReplyCommits(offset: -20), isFalse);
      expect(QlDuration.swipeSnap, const Duration(milliseconds: 180));
    },
  );

  testWidgets('swipe-reply start threshold uses 0.4cm', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2, size: Size(400, 800)),
        child: const SizedBox(),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    expect(
      messageSwipeReplyStartPx(context),
      closeTo(qlEdgeStartPx(MediaQuery.devicePixelRatioOf(context)), 0.0001),
    );
  });
}
