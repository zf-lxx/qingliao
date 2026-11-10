// Headless Flutter-rendered artifacts, not a browser/Chromium capture.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_chat_demo/main.dart';

void main() {
  testWidgets('桌面/手机截图与真实 Flutter 动画帧', (tester) async {
    await tester.runAsync(() async {
      final regular = FontLoader('ChatSans')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('assets/fonts/ChatSans.otf').readAsBytes(),
            ),
          ),
        );
      await regular.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('build/web/assets/fonts/MaterialIcons-Regular.otf')
                  .readAsBytes(),
            ),
          ),
        );
      await icons.load();
      final emoji = FontLoader('ChatEmoji')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('assets/fonts/ChatEmoji.ttf').readAsBytes(),
            ),
          ),
        );
      await emoji.load();
    });
    final root = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    await tester.pumpWidget(
      RepaintBoundary(key: root, child: const ChatDemo()),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    Future<void> shot(String path) async {
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('shots/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    int frame = 0;
    Future<void> record(int count) async {
      for (int i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 33));
        await shot('frames/frame_${(frame++).toString().padLeft(3, '0')}.png');
      }
    }

    await shot('01-desktop-welcome.png');
    await record(12);
    await tester.tap(find.byKey(const ValueKey('contact-林间设计室')));
    await tester.pump();
    await record(12);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await shot('02-desktop-chat.png');
    await record(12);
    await tester.enterText(
      find.byKey(const ValueKey('message-input')),
      '把每一个细节，做得刚刚好。',
    );
    await record(10);
    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pump();
    await tester.pump();
    await record(12);
    await shot('03-message-sent.png');
    await record(12);
    await tester.tap(find.byTooltip('动态贴纸'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await shot('04-sticker-panel.png');
    await tester.tap(find.byTooltip('动态贴纸'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('把每一个细节，做得刚刚好。').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.longPress(find.text('把每一个细节，做得刚刚好。').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await shot('05-reactions-menu.png');
    await tester.tap(find.text('❤'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 170));
    await shot('06-reaction-burst.png');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.binding.setSurfaceSize(const Size(412, 860));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot('07-mobile-chat.png');
    // A drag from the left edge closes the chat, then the list can reopen it.
    await tester.dragFrom(const Offset(8, 380), const Offset(160, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('message-input')), findsNothing);
    await shot('08-mobile-list.png');
    await tester.tap(find.byKey(const ValueKey('contact-小夏')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('细节会被感受到 ✨'));
    await tester.pump();
    await tester.drag(find.text('细节会被感受到 ✨'), const Offset(120, 0));
    await tester.pump();
    expect(find.text('回复消息'), findsOneWidget);
    await shot('09-mobile-swipe-reply.png');
    await tester.pumpWidget(const SizedBox());
  });
}
