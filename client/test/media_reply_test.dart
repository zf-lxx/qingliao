import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/widgets/reply_quote.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;

void main() {
  test('media reply labels and CST dates never produce empty previews', () {
    for (final pair in [
      ('image', '图片'),
      ('video', '视频'),
      ('file', '文件'),
      ('voice', '语音'),
    ]) {
      expect(replyPreview({'kind': pair.$1, 'text': ''}), pair.$2);
    }
    expect(replyPreview(null), '消息已删除');
    expect(replyPreview({'deleted': true}), '消息已删除');
    expect(replyPreview({'kind': 'image', 'text': '图片说明'}), '图片说明');
    expect(messageDay({'created_at': '2026-11-10T16:04:00Z'}), '2026-11-11');
  });
  testWidgets(
    'real image reply has sender + media preview, invalid reply values have no quote',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final engine = ChatEngine(store, MemoryVault());
      engine.session = {'user_id': 'me'};
      engine.users['peer'] = {'display_name': '测试用户'};
      engine.messages['image'] = {
        'id': 'image',
        'sender_id': 'peer',
        'kind': 'image',
        'text': '',
      };
      Future<void> bubble(dynamic reply) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Bubble(
              engine: engine,
              message: {
                'id': 'reply',
                'sender_id': 'me',
                'conversation_id': 'chat',
                'kind': 'text',
                'text': '9999',
                'reply_to': reply,
                'created_at': '2026-11-10T16:04:00Z',
              },
              onLongPress: () {},
              onReply: () {},
            ),
          ),
        ),
      );
      await bubble('image');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('测试用户'), findsOneWidget);
      expect(find.text('图片'), findsOneWidget);
      expect(find.byKey(const Key('reply-quote')), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      for (final invalid in [null, '', 0, '0', <String, dynamic>{}]) {
        await bubble(invalid);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('reply-quote')), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await engine.shutdown();
      await tester.runAsync(store.close);
    },
  );
}
