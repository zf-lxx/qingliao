import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/cells/bubble_path.dart';
import 'package:qingliao/cells/link_preview_card.dart';
import 'package:qingliao/cells/message_layout.dart';
import 'package:qingliao/cells/text_message_cell.dart';
import 'package:qingliao/ui/chat/chat_widgets.dart';
import 'package:qingliao/cells/row_height.dart';
import 'package:qingliao/compositor/insert_shift.dart';
import 'package:qingliao/compositor/message_enter_transition.dart';
import 'package:qingliao/compositor/swipe_reply.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/media/chat_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

void main() {
  test('bubble path uses 83-degree tail, not a triangle', () {
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

  test('native text cell is only for plain stored text without extras', () {
    expect(usesNativeTextCell({'kind': 'text', 'text': 'hi'}), isTrue);
    expect(usesNativeTextCell({'kind': 'image', 'text': ''}), isFalse);
    expect(
      usesNativeTextCell({'kind': 'text', 'text': 'hi', 'reply_to': 'm1'}),
      isTrue,
    );
    expect(hasReplyQuote({'kind': 'text', 'reply_to': 'm1'}), isTrue);
    expect(usesNativeTextCell({'kind': 'text', 'deleted': true}), isFalse);
    expect(
      usesNativeTextCell({
        'kind': 'text',
        'text': 'https://example.com',
        'link_preview': {'title': 'Example', 'url': 'https://example.com'},
      }),
      isTrue,
    );
    expect(
      estimateRowHeight({'kind': 'image'}, 360),
      greaterThan(estimateRowHeight({'kind': 'text', 'text': 'hi'}, 360)),
    );
  });

  testWidgets('plain text bubbles use the native cell with corner stamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(360, 640)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TextMessageCell(text: '测试消息1', stamp: '00:04', mine: false),
        ),
      ),
    );
    expect(find.byKey(const Key('native-text-cell')), findsOneWidget);
    expect(find.text('00:04'), findsOneWidget);
    expect(find.byKey(const Key('native-text')), findsOneWidget);
    expect(
      (tester.widget<Text>(find.byKey(const Key('native-text')))).data,
      '测试消息1',
    );
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

  testWidgets('chat page send uses native cell and does not leave overlay', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final engine = HistoryEngine(store, MemoryVault())
      ..session = {'user_id': 'me'}
      ..online = true;
    engine.dialogs['chat'] = {'id': 'chat', 'kind': 'direct'};
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            disableAnimations: true,
          ),
          child: ChatPage(engine: engine, cid: 'chat', title: '测试聊天'),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byKey(const Key('composer')), '自绘发送');
    await tester.tap(find.byKey(const Key('send')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('entity-text')), findsOneWidget);
    expect(find.byType(MessageEnterLayer), findsNothing);
    expect(find.byKey(const Key('native-text-cell')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await engine.shutdown();
    await tester.runAsync(store.close);
  });

  testWidgets('image box keeps 240x160 before bytes arrive', (tester) async {
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatImage(
            future: pending.future,
            heroTag: 'img',
            sender: '你',
            time: '00:04',
            onRetry: () {},
          ),
        ),
      ),
    );
    final box = tester.getSize(find.byKey(const Key('chat-image-box')));
    expect(box.width, ChatImage.boxWidth);
    expect(box.height, ChatImage.boxHeight);
    pending.complete(Uint8List(8));
  });

  testWidgets('insert shift starts below and settles at zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InsertShift(
          generation: 1,
          amount: 56,
          enabled: true,
          child: SizedBox(width: 40, height: 20, child: Text('旧消息')),
        ),
      ),
    );
    await tester.pump();
    final start = tester.getTopLeft(find.text('旧消息')).dy;
    await tester.pump(const Duration(milliseconds: 250));
    final end = tester.getTopLeft(find.text('旧消息')).dy;
    expect(start, greaterThan(end));
  });

  testWidgets('left swipe replies at 50dp, clamps 80dp, snaps 180ms', (
    tester,
  ) async {
    var replies = 0;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), devicePixelRatio: 1),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipeReply(
                enabled: true,
                onReply: () => replies++,
                child: const SizedBox(
                  width: 220,
                  height: 80,
                  child: Text('可滑回复'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final start = tester.getTopLeft(find.text('可滑回复')).dx;
    final g = await tester.startGesture(tester.getCenter(find.text('可滑回复')));
    await g.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('可滑回复')).dx, start);
    await g.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('可滑回复')).dx, start);
    await g.moveBy(const Offset(-55, 0));
    await tester.pump();
    final pulled = tester.getTopLeft(find.text('可滑回复')).dx;
    expect(start - pulled, greaterThanOrEqualTo(SwipeReply.trigger));
    expect(start - pulled, lessThanOrEqualTo(SwipeReply.maxPull));
    await g.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(start - tester.getTopLeft(find.text('可滑回复')).dx, SwipeReply.maxPull);
    await g.up();
    await tester.pumpAndSettle();
    expect(replies, 1);
    expect(tester.getTopLeft(find.text('可滑回复')).dx, start);
  });

  testWidgets('incoming rows shift 35dp in select mode, outgoing stay put', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(360, 640)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              TgSelectableMessage(
                selecting: true,
                selected: true,
                outgoing: false,
                onToggle: _noop,
                child: SizedBox(key: Key('in'), width: 80, height: 40),
              ),
              TgSelectableMessage(
                selecting: true,
                selected: false,
                outgoing: true,
                onToggle: _noop,
                child: SizedBox(key: Key('out'), width: 80, height: 40),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final incoming = tester.getTopLeft(find.byKey(const Key('in'))).dx;
    final outgoing = tester.getTopLeft(find.byKey(const Key('out'))).dx;
    expect(incoming - outgoing, 35);
  });

  testWidgets('link preview sits inside the native cell', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(360, 640)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TextMessageCell(
            text: '看这个链接',
            stamp: '00:04',
            mine: false,
            preview: LinkPreviewCard(
              preview: {
                'site_name': 'example.com',
                'title': 'Example',
                'description': 'desc',
                'url': 'https://example.com/',
              },
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('native-text-cell')), findsOneWidget);
    expect(find.byKey(const Key('link-preview')), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
  });

  test('composer text rect starts inside the field, not the whole bar', () {
    final field = const Rect.fromLTWH(20, 500, 280, 48);
    final start = composerTextRect(field: field, text: '你好');
    expect(start.left, greaterThan(field.left));
    expect(start.width, lessThan(field.width));
    expect(start.height, lessThanOrEqualTo(field.height));
  });

  test('second send keeps the first flight until it completes', () {
    final c = MessageEnterController();
    c.begin(
      const MessageEnterFlight(
        id: 'a',
        text: '一',
        stamp: '00:01',
        from: Rect.fromLTWH(0, 10, 40, 20),
        to: Rect.fromLTWH(80, 0, 80, 40),
      ),
    );
    c.begin(
      const MessageEnterFlight(
        id: 'b',
        text: '二',
        stamp: '00:02',
        from: Rect.fromLTWH(0, 10, 40, 20),
        to: Rect.fromLTWH(80, 0, 80, 40),
      ),
    );
    expect(c.flights.map((f) => f.id), ['a', 'b']);
    expect(c.hides('a'), isTrue);
    c.complete('a');
    expect(c.hides('a'), isFalse);
    expect(c.hides('b'), isTrue);
  });
}

void _noop() {}
