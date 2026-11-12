import 'chat_image.dart';
import 'message_layout.dart';

/// Best-effort height of an incoming row so neighbors can shift by the real
/// insert size instead of a constant 56.
double estimateRowHeight({
  required String kind,
  required String text,
  required double viewportWidth,
  bool hasReply = false,
}) {
  if (kind == 'image' || kind == 'photo' || kind == 'video') {
    return ChatImageBox.boxHeight +
        StampLayout.padTop +
        StampLayout.padBottom +
        8;
  }
  final layout = StampLayout.measure(
    text: text.isEmpty ? ' ' : text,
    stamp: '00:00',
    viewportWidth: viewportWidth,
    headerHeight: hasReply ? 44 : 0,
    checksWidth: 18,
  );
  return layout.bubbleHeight + 8;
}
