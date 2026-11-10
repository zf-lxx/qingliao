import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_chat_demo/main.dart';

void main() {
  testWidgets('聊天入口、输入、贴纸、回复菜单均可交互', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    await tester.pumpWidget(const ChatDemo());
    await tester.pump();
    expect(find.text('让对话，自然发生。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('contact-林间设计室')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('message-input')),
      '测试发送动画',
    );
    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('测试发送动画'), findsAtLeastNWidgets(1));
    await tester.tap(find.byTooltip('动态贴纸'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('原创动态贴纸  /  CC0 1.0'), findsOneWidget);
    await tester.tap(find.byTooltip('动态贴纸'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('测试发送动画').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.longPress(find.text('测试发送动画').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('回复'), findsOneWidget);
    await tester.tap(find.text('回复'));
    await tester.pump();
    expect(find.text('回复消息'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
