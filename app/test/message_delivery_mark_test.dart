import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/chat_message_merge.dart';
import 'package:qingliao/chat/message_delivery_mark.dart';
import 'package:qingliao/tdlib/td_models.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

ChatMessage _outgoing(int id, {bool sending = false, bool ack = false}) =>
    ChatMessage(
      id: id,
      isOutgoing: true,
      text: 'hi',
      date: 1,
      isSending: sending,
      isSendAcknowledged: ack,
    );

void main() {
  testWidgets('sending keeps the spinning arc and sending key', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MessageDeliveryMark(
          isSending: true,
          isRead: false,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('messageDeliverySending')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('messageDeliverySent')), findsNothing);
    expect(find.byKey(const ValueKey('messageDeliveryRead')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('messageDeliverySending'))),
      const Size(10, 10),
    );
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('sent unread is a single check at the sent size', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MessageDeliveryMark(
          isSending: false,
          isRead: false,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('messageDeliverySent')), findsOneWidget);
    expect(find.byKey(const ValueKey('messageDeliverySending')), findsNothing);
    expect(find.byKey(const ValueKey('messageDeliveryRead')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('messageDeliverySent'))),
      const Size(10, 10),
    );
    expect(find.byIcon(Icons.done), findsNothing);
  });

  testWidgets('read is a slightly wider double check', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MessageDeliveryMark(
          isSending: false,
          isRead: true,
          color: Color(0xFF6EB8FF),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('messageDeliveryRead')), findsOneWidget);
    expect(find.byKey(const ValueKey('messageDeliverySent')), findsNothing);
    final size = tester.getSize(
      find.byKey(const ValueKey('messageDeliveryRead')),
    );
    expect(size.height, 10);
    expect(size.width, closeTo(13.6, 0.01));
    expect(size.width, greaterThan(10));
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  test('width helper keeps height-sized sent marks and widens read marks', () {
    expect(messageDeliveryMarkWidth(isSending: true, isRead: false), 10);
    expect(messageDeliveryMarkWidth(isSending: false, isRead: false), 10);
    expect(
      messageDeliveryMarkWidth(isSending: false, isRead: true),
      closeTo(13.6, 0.01),
    );
  });

  test('chatOutgoingDelivery reuses the existing read frontier', () {
    expect(
      chatOutgoingDelivery(
        message: _outgoing(10, sending: true),
        lastReadOutboxId: 99,
      )?.isSending,
      isTrue,
    );
    expect(
      chatOutgoingDelivery(
        message: _outgoing(10, sending: true),
        lastReadOutboxId: 99,
      )?.isRead,
      isFalse,
    );
    final sent = chatOutgoingDelivery(
      message: _outgoing(150),
      lastReadOutboxId: 100,
    );
    expect(sent?.isSending, isFalse);
    expect(sent?.isRead, isFalse);
    final read = chatOutgoingDelivery(
      message: _outgoing(80),
      lastReadOutboxId: 100,
    );
    expect(read?.isSending, isFalse);
    expect(read?.isRead, isTrue);
    expect(
      chatOutgoingDelivery(message: _outgoing(80), lastReadOutboxId: 0)?.isRead,
      isFalse,
    );
    expect(
      chatOutgoingDelivery(
        message: ChatMessage(id: 80, isOutgoing: false, text: 'in', date: 1),
        lastReadOutboxId: 100,
      ),
      isNull,
    );
    expect(
      isOutgoingServerMessageRead(message: _outgoing(80), lastReadOutboxId: 0),
      isFalse,
    );
  });

  test('list row delivery follows last outgoing message and outbox id', () {
    final sent = ChatSummary(
      id: 1,
      title: 'a',
      lastMessage: 'hi',
      lastMessageId: 150,
      date: 1,
      unreadCount: 0,
      lastReadOutboxMessageId: 100,
      order: 1,
      isMuted: false,
      lastChatMessage: _outgoing(150),
    );
    expect(chatListOutgoingDelivery(sent)?.isRead, isFalse);
    sent.lastReadOutboxMessageId = 150;
    expect(chatListOutgoingDelivery(sent)?.isRead, isTrue);
    sent.lastReadOutboxMessageId = 0;
    expect(chatListOutgoingDelivery(sent)?.isRead, isFalse);
  });

  test('painter flags a change when sent becomes read', () {
    final sent = MessageDeliveryPainter(
      isSending: false,
      isRead: false,
      color: const Color(0xFFFFFFFF),
    );
    final read = MessageDeliveryPainter(
      isSending: false,
      isRead: true,
      color: const Color(0xFF6EB8FF),
    );
    expect(read.shouldRepaint(sent), isTrue);
    expect(sent.shouldRepaint(sent), isFalse);
  });
}
