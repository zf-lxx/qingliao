import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tdlib/td_models.dart';
import 'chat_message_merge.dart';

/// Height of the delivery mark used next to a bubble stamp or list timestamp.
const double kMessageDeliveryMarkSize = 10;

/// Width reserved for a delivery mark of [size] height.
double messageDeliveryMarkWidth({
  required bool isSending,
  required bool isRead,
  double size = kMessageDeliveryMarkSize,
}) => isSending || !isRead ? size : size * 1.36;

/// Outgoing delivery state for a chat-list row or bubble, using the existing
/// peer-read frontier ([isOutgoingServerMessageRead]).
class ChatOutgoingDelivery {
  const ChatOutgoingDelivery({required this.isSending, required this.isRead});

  /// True while the message is still waiting for a server acknowledgement.
  final bool isSending;
  final bool isRead;
}

ChatOutgoingDelivery? chatOutgoingDelivery({
  required ChatMessage? message,
  required int lastReadOutboxId,
}) {
  if (message == null || !message.isOutgoing) return null;
  return ChatOutgoingDelivery(
    isSending: message.isSending && !message.isSendAcknowledged,
    isRead: isOutgoingServerMessageRead(
      message: message,
      lastReadOutboxId: lastReadOutboxId,
    ),
  );
}

ChatOutgoingDelivery? chatListOutgoingDelivery(ChatSummary chat) =>
    chatOutgoingDelivery(
      message: chat.lastChatMessage,
      lastReadOutboxId: chat.lastReadOutboxMessageId,
    );

/// Sending spinner, or a short single / double check once settled.
class MessageDeliveryMark extends StatelessWidget {
  const MessageDeliveryMark({
    super.key,
    required this.isSending,
    required this.isRead,
    required this.color,
    this.size = kMessageDeliveryMarkSize,
  });

  final bool isSending;
  final bool isRead;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isSending) {
      return MessageDeliverySendingIndicator(color: color, size: size);
    }
    return MessageDeliverySettledMark(isRead: isRead, color: color, size: size);
  }
}

/// The settled tick: no controller, no ticker. Only the in-flight spinner needs
/// an animation, and every outgoing bubble used to mount one to draw a mark.
class MessageDeliverySettledMark extends StatelessWidget {
  const MessageDeliverySettledMark({
    super.key,
    required this.isRead,
    required this.color,
    required this.size,
  });

  final bool isRead;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey(isRead ? 'messageDeliveryRead' : 'messageDeliverySent'),
    width: messageDeliveryMarkWidth(
      isSending: false,
      isRead: isRead,
      size: size,
    ),
    height: size,
    child: CustomPaint(
      painter: MessageDeliveryPainter(
        isSending: false,
        isRead: isRead,
        color: color,
      ),
    ),
  );
}

class MessageDeliverySendingIndicator extends StatefulWidget {
  const MessageDeliverySendingIndicator({
    super.key,
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  State<MessageDeliverySendingIndicator> createState() =>
      _MessageDeliverySendingIndicatorState();
}

class _MessageDeliverySendingIndicatorState
    extends State<MessageDeliverySendingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: const ValueKey('messageDeliverySending'),
    dimension: widget.size,
    // Its own layer: the painter repaints on every tick, and without a
    // boundary that re-records the whole outgoing bubble at 60fps for the
    // entire send.
    child: RepaintBoundary(
      child: CustomPaint(
        painter: MessageDeliveryPainter(
          rotation: _controller,
          isSending: true,
          isRead: false,
          color: widget.color.withValues(alpha: 0.72),
        ),
      ),
    ),
  );
}

class MessageDeliveryPainter extends CustomPainter {
  MessageDeliveryPainter({
    Animation<double>? rotation,
    required this.isSending,
    required this.isRead,
    required this.color,
  }) : _rotation = rotation,
       super(repaint: rotation);

  final Animation<double>? _rotation;
  final bool isSending;
  final bool isRead;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (isSending) {
      final strokeWidth = math.max(1.25, size.shortestSide * 0.16);
      final radius = (size.shortestSide - strokeWidth) / 2;
      final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: radius,
      );
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        (_rotation?.value ?? 0.0) * math.pi * 2 - math.pi / 2,
        math.pi * 1.35,
        false,
        paint,
      );
      return;
    }

    final height = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.15, height * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (isRead) {
      _drawCheck(canvas, Offset.zero, height, paint);
      _drawCheck(canvas, Offset(height * 0.36, 0), height, paint);
    } else {
      _drawCheck(canvas, Offset.zero, height, paint);
    }
  }

  void _drawCheck(Canvas canvas, Offset origin, double size, Paint paint) {
    final path = Path()
      ..moveTo(origin.dx + size * 0.12, origin.dy + size * 0.54)
      ..lineTo(origin.dx + size * 0.36, origin.dy + size * 0.78)
      ..lineTo(origin.dx + size * 0.88, origin.dy + size * 0.22);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MessageDeliveryPainter oldDelegate) =>
      oldDelegate.isSending != isSending ||
      oldDelegate.isRead != isRead ||
      oldDelegate.color != color;
}
