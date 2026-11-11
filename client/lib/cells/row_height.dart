import '../media/chat_image.dart';
import 'message_layout.dart';

/// Best-effort height of an incoming row so neighbors can shift by the real
/// insert size instead of a constant 56.
double estimateRowHeight(Map<String, dynamic> message, double viewportWidth) {
  if (message['kind'] == 'image') {
    return ChatImage.boxHeight + StampLayout.padTop + StampLayout.padBottom + 8;
  }
  final text = message['text']?.toString() ?? '';
  final hasReply = hasReplyQuote(message);
  final layout = StampLayout.measure(
    text: text.isEmpty ? ' ' : text,
    stamp: '00:00',
    viewportWidth: viewportWidth,
    headerHeight: hasReply ? 44 : 0,
    checksWidth: 18,
  );
  return layout.bubbleHeight + 8;
}
