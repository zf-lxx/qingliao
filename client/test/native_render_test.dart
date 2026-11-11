import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/cells/message_layout.dart';
import 'package:qingliao/cells/text_message_cell.dart';
import 'package:qingliao/compositor/insert_shift.dart';
import 'package:qingliao/compositor/message_enter_transition.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/media/chat_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

void main() {
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
      isFalse,
    );
    expect(usesNativeTextCell({'kind': 'text', 'deleted': true}), isFalse);
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
                text: '发送飞入',
                stamp: '00:04',
                from: const Rect.fromLTWH(20, 500, 280, 48),
                to: const Rect.fromLTWH(80, 200, 200, 56),
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
    expect(find.text('自绘发送', findRichText: true), findsWidgets);
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
}
