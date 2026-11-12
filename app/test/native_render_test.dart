import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/render/bubble_path.dart';
import 'package:qingliao/render/bubble_stamp.dart';
import 'package:qingliao/render/chat_image.dart';
import 'package:qingliao/render/insert_shift.dart';
import 'package:qingliao/render/media_cache.dart';
import 'package:qingliao/render/message_enter.dart';
import 'package:qingliao/render/message_layout.dart';
import 'package:qingliao/render/ql_curves.dart';
import 'package:qingliao/render/row_height.dart';

void main() {
  test('bubble path uses an 83-degree tail, not a triangle', () {
    final outgoing = qingliaoBubblePath(
      const Rect.fromLTWH(0, 0, 120, 48),
      mine: true,
    );
    final incoming = qingliaoBubblePath(
      const Rect.fromLTWH(0, 0, 120, 48),
      mine: false,
    );
    expect(outgoing.contains(const Offset(120 - 2.6, 46)), isTrue);
    expect(incoming.contains(const Offset(2.6, 46)), isTrue);
    final grouped = qingliaoBubblePath(
      const Rect.fromLTWH(0, 0, 120, 48),
      mine: true,
      grouped: true,
    );
    expect(grouped.contains(const Offset(118, 46)), isFalse);
    final media = qingliaoBubblePath(
      const Rect.fromLTWH(0, 0, 120, 80),
      mine: true,
      media: true,
    );
    expect(media.contains(const Offset(117, 40)), isTrue);
  });

  test('short text keeps stamp on the same line; long text wraps below', () {
    final short = StampLayout.measure(
      text: '你好',
      stamp: '00:04',
      viewportWidth: 360,
    );
    expect(short.sameLine, isTrue);
    expect(short.bubbleHeight, lessThan(48));
    final long = StampLayout.measure(
      text: '这是一条需要换行的中文消息，用来确认时间戳不会和正文抢同一行宽度。' * 2,
      stamp: '00:04',
      viewportWidth: 360,
    );
    expect(long.sameLine, isFalse);
    expect(long.bubbleHeight, greaterThan(short.bubbleHeight));
  });

  test('clustered bubbles drop the tail only for a continuous neighbor', () {
    expect(
      isClusteredWithNewer(
        sameSender: true,
        separatedByTimeOrTopic: false,
        newerIsService: false,
      ),
      isTrue,
    );
    expect(
      isClusteredWithNewer(
        sameSender: true,
        separatedByTimeOrTopic: true,
        newerIsService: false,
      ),
      isFalse,
    );
  });

  test('row height for photos is larger than a short text row', () {
    expect(
      estimateRowHeight(kind: 'image', text: '', viewportWidth: 360),
      greaterThan(
        estimateRowHeight(kind: 'text', text: 'hi', viewportWidth: 360),
      ),
    );
  });

  test('back gesture durations and scrim follow the documented floors', () {
    expect(qlBackFinishDuration(100, 400).inMilliseconds, 50);
    expect(qlBackFinishDuration(400, 400).inMilliseconds, 200);
    expect(qlBackCancelDuration(50, 400).inMilliseconds, 120);
    expect(qlBackCancelDuration(400, 400).inMilliseconds, 320);
    expect(qlBackScrimOpacity(0), 0);
    expect(qlBackScrimOpacity(0.8), closeTo(96 / 255, 0.0001));
    expect(qlBackScrimOpacity(1), closeTo(96 / 255, 0.0001));
    expect(qlBackPageScale(0), 1);
    expect(qlBackPageScale(56), closeTo(0.95, 0.0001));
  });

  testWidgets('enter overlay interpolates then dismisses', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              MessageEnterLayer(
                flight: const MessageEnterFlight(
                  id: 'enter-1',
                  text: '发送飞入',
                  stamp: '00:04',
                  from: Rect.fromLTWH(20, 500, 280, 48),
                  to: Rect.fromLTWH(80, 200, 200, 56),
                ),
                onDone: () => done = true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('发送飞入'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    expect(done, isFalse);
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('concurrent flights can overlap', (tester) async {
    final controller = MessageEnterController();
    controller.begin(
      const MessageEnterFlight(
        id: 'a',
        text: '第一条',
        stamp: '00:01',
        from: Rect.fromLTWH(20, 500, 200, 40),
        to: Rect.fromLTWH(80, 200, 180, 48),
      ),
    );
    controller.begin(
      const MessageEnterFlight(
        id: 'b',
        text: '第二条',
        stamp: '00:02',
        from: Rect.fromLTWH(20, 500, 200, 40),
        to: Rect.fromLTWH(80, 260, 180, 48),
      ),
    );
    expect(controller.flights, hasLength(2));
    expect(controller.hides('a') && controller.hides('b'), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Scaffold(
            body: Stack(
              children: [
                for (final flight in controller.flights)
                  MessageEnterLayer(
                    key: ValueKey(flight.id),
                    flight: flight,
                    onDone: () => controller.complete(flight.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(controller.flights, isEmpty);
  });

  testWidgets('insert shift starts from the real height and settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(360, 640)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: InsertShift(
            generation: 1,
            amount: 64,
            enabled: true,
            child: SizedBox(key: Key('shifted'), height: 20, width: 20),
          ),
        ),
      ),
    );
    final start = tester.getTopLeft(find.byKey(const Key('shifted')));
    expect(start.dy, closeTo(64, 0.5));
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(find.byKey(const Key('shifted')));
    expect(end.dy, closeTo(0, 0.5));
  });

  testWidgets('image box keeps 240x160 before bytes arrive', (tester) async {
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatImageBox(future: pending.future)),
      ),
    );
    final box = tester.getSize(find.byKey(const Key('chat-image-box')));
    expect(box.width, ChatImageBox.boxWidth);
    expect(box.height, ChatImageBox.boxHeight);
    pending.complete(Uint8List(8));
    await tester.pump();
  });

  test('media cache serves the second load from disk', () async {
    final dir = Directory.systemTemp.createTempSync('ql-media-test-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final cache = MediaCache(root: dir);
    var fetches = 0;
    Future<Uint8List> fetch() async {
      fetches++;
      return Uint8List.fromList([1, 2, 3]);
    }

    final first = await cache.load('abc', fetch);
    expect(first, [1, 2, 3]);
    // New cache instance, same disk, no in-memory future.
    final again = MediaCache(root: dir);
    final second = await again.load('abc', fetch);
    expect(second, [1, 2, 3]);
    expect(fetches, 1);
  });
}
