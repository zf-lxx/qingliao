import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/message_swipe_reply.dart';

class _TestTicker extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  test('start, trigger and limit use the wider anti-misfire distances', () {
    expect(messageSwipeReplyStartCm, 1.2);
    expect(
      messageSwipeReplyStartDistance(),
      closeTo((1.2 / 2.54) * 160, 0.0001),
    );
    expect(messageSwipeReplyTrigger, 96);
    expect(messageSwipeReplyHardLimit, 120);
    expect(messageSwipeReplyOffset(-120), -120);
    expect(messageSwipeReplyOffset(-200), -120);
    expect(messageSwipeReplyOffset(20), 0);
    expect(messageSwipeReplyCommits(offset: -96), isTrue);
    expect(messageSwipeReplyCommits(offset: -50), isFalse);
    expect(
      messageSwipeReplyCommits(offset: -20, primaryVelocity: -8000),
      isFalse,
    );
  });

  test('direction gate requires a clearly leftward, horizontal drag', () {
    const start = 75.6;
    expect(
      messageSwipeReplyAcceptsDirection(dx: -80, dy: 10, startPx: start),
      isTrue,
    );
    expect(
      messageSwipeReplyAcceptsDirection(dx: -80, dy: -50, startPx: start),
      isFalse,
    );
    expect(
      messageSwipeReplyAcceptsDirection(dx: -40, dy: 0, startPx: start),
      isFalse,
    );
    expect(
      messageSwipeReplyRejectsAsScroll(dx: -10, dy: -80, startPx: start),
      isTrue,
    );
    expect(
      messageSwipeReplyRejectsAsScroll(dx: 80, dy: 0, startPx: start),
      isTrue,
    );
    expect(
      messageSwipeReplyRejectsAsScroll(dx: -20, dy: 0, startPx: start),
      isFalse,
    );
  });

  testWidgets(
    'a mostly vertical drag is rejected and does not commit a reply',
    (tester) async {
      final controller = MessageSwipeReplyController(vsync: _TestTicker());
      addTearDown(controller.dispose);
      var replied = false;
      controller.beginDrag(startPx: 76);
      controller.dragBy(-20, dy: -60);
      expect(controller.offset, 0);
      controller.finish(onReply: () => replied = true);
      expect(replied, isFalse);
      expect(controller.offset, 0);
    },
  );

  testWidgets(
    'crossing the trigger ticks once and commits; short drags spring home',
    (tester) async {
      final controller = MessageSwipeReplyController(vsync: _TestTicker());
      addTearDown(controller.dispose);
      controller.settleDuration = const Duration(milliseconds: 1);
      var replied = false;
      controller.beginDrag();
      controller.dragBy(-50);
      expect(controller.offset, closeTo(-50, 0.001));
      expect(controller.tickCount, 0);
      controller.finish(onReply: () => replied = true);
      expect(replied, isFalse);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);

      controller.beginDrag();
      controller.dragBy(-96);
      expect(controller.tickCount, 1);
      controller.dragBy(-10);
      expect(controller.tickCount, 1);
      controller.finish(onReply: () => replied = true);
      expect(replied, isTrue);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
    },
  );
}
