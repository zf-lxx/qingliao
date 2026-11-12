import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingliao/chat/chat_view_model.dart';
import 'package:qingliao/chat/message_bubble.dart';
import 'package:qingliao/qingliao/ql_ids.dart';
import 'package:qingliao/tdlib/td_client.dart';
import 'package:qingliao/tdlib/td_models.dart';
import 'package:qingliao/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _tdMessage({
  required int id,
  int replyToMessageId = 0,
  String text = '斑斑驳驳',
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 7,
  'date': 1700000000,
  'is_outgoing': true,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 1},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
  'reply_to': {
    '@type': 'messageReplyToMessage',
    'chat_id': 7,
    'message_id': replyToMessageId,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  final requests = <Map<String, dynamic>>[];
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) onQuery;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 1,
        accountUserId: 1,
        query: (request) async {
          requests.add(request);
          return onQuery(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    requests.clear();
    onQuery = (request) async => switch (request['@type']) {
      'getCustomEmojiStickers' => <String, dynamic>{
        '@type': 'stickers',
        'stickers': const <Map<String, dynamic>>[],
      },
      'getChatHistory' => <String, dynamic>{
        '@type': 'messages',
        'messages': const <Object>[],
      },
      'getRepliedMessage' => _tdMessage(id: qlMessageId(11), text: '斑斑驳驳'),
      _ => <String, dynamic>{'@type': 'ok'},
    };
  });

  test('qlReplyMessageId falls through a zero reply_to_seq to the ref', () {
    expect(qlReplyMessageId(replyToSeq: 30), qlMessageId(30));
    expect(qlReplyMessageId(replyToSeq: 0, refSeq: 11), qlMessageId(11));
    expect(qlReplyMessageId(replyToSeq: null, refSeq: 11), qlMessageId(11));
    expect(qlReplyMessageId(replyToSeq: 0), 0);
    expect(qlReplyMessageId(), 0);
    // The old `_int(0) ?? ref` pitfall: 0 is not null, so the ref was ignored.
    expect(qlReplyMessageId(replyToSeq: 0, refSeq: 4) != 0, isTrue);
  });

  test('TDParse treats a zero reply message_id as missing', () {
    final zero = TDParse.message(_tdMessage(id: 20, replyToMessageId: 0));
    expect(zero, isNotNull);
    expect(zero!.replyToMessageId, isNull);

    final ok = TDParse.message(
      _tdMessage(id: 20, replyToMessageId: qlMessageId(11)),
    );
    expect(ok!.replyToMessageId, qlMessageId(11));
  });

  test('resolveReplyTarget uses getRepliedMessage when the target id is 0', () async {
    final reply = TDParse.message(
      _tdMessage(id: qlMessageId(12), replyToMessageId: 0),
    )!;
    expect(reply.replyToMessageId, isNull);
    final vm = ChatViewModel(
      chatId: 7,
      title: '测试用户',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    expect(await vm.resolveReplyTarget(reply), qlMessageId(11));
    expect(
      requests.any(
        (r) =>
            r['@type'] == 'getRepliedMessage' &&
            r['message_id'] == qlMessageId(12),
      ),
      isTrue,
    );
  });

  Future<void> pumpQuote(
    WidgetTester tester, {
    required ChatMessage message,
    ValueChanged<int>? onOpenReply,
    ValueChanged<ChatMessage>? onOpenReplyQuote,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: '测试用户',
              isGroup: false,
              onOpenReply: onOpenReply,
              onOpenReplyQuote: onOpenReplyQuote,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('tapping a text-only reply quote opens the original', (tester) async {
    ChatMessage? openedQuote;
    var openedId = 0;
    final textReply =
        ChatMessage(
            id: qlMessageId(12),
            chatId: 7,
            isOutgoing: true,
            text: '斑斑驳驳',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: qlMessageId(11),
            replyToDate: 1,
          )
          ..replyToSender = 'admin'
          ..replyToPreview = '斑斑驳驳';

    await pumpQuote(
      tester,
      message: textReply,
      onOpenReply: (id) => openedId = id,
      onOpenReplyQuote: (message) => openedQuote = message,
    );

    expect(find.byKey(const ValueKey('messageReplyMediaPreview')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
    await tester.pump();
    expect(openedQuote?.id, qlMessageId(12));
    expect(openedQuote?.replyToMessageId, qlMessageId(11));
    // The quote callback is preferred; the int callback is the fallback path.
    expect(openedId, 0);
  });

  testWidgets('a text quote with a missing target id still fires the quote callback', (
    tester,
  ) async {
    ChatMessage? openedQuote;
    final textReply =
        ChatMessage(
            id: qlMessageId(12),
            chatId: 7,
            isOutgoing: true,
            text: '斑斑驳驳',
            date: 1,
            contentType: 'messageText',
            replyToDate: 1,
          )
          ..replyToSender = 'admin'
          ..replyToPreview = '斑斑驳驳';

    await pumpQuote(
      tester,
      message: textReply,
      onOpenReplyQuote: (message) => openedQuote = message,
    );
    await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
    await tester.pump();
    expect(openedQuote?.id, qlMessageId(12));
    expect(openedQuote?.replyToMessageId, isNull);
  });
}
