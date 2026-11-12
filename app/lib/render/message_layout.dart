import 'package:flutter/painting.dart';

/// Layout for embedding the timestamp in the last line of text, instead of a
/// separate row that always grows the bubble.
class StampLayout {
  static const padLeft = 12.0,
      padRight = 10.0,
      padTop = 9.0,
      padBottom = 6.0,
      tail = 8.0,
      stampGap = 6.0,
      maxFraction = .80,
      maxCap = 650.0;
  static const textStyle = TextStyle(
    fontSize: 15,
    height: 1.45,
    color: Color(0xffeef4fa),
  );
  static const stampStyle = TextStyle(
    fontSize: 10,
    height: 1.1,
    color: Color(0xff7d91a5),
  );

  final double bubbleWidth, bubbleHeight, innerWidth, stampWidth, stampHeight;
  final bool sameLine;
  const StampLayout({
    required this.bubbleWidth,
    required this.bubbleHeight,
    required this.innerWidth,
    required this.stampWidth,
    required this.stampHeight,
    required this.sameLine,
  });

  double get suffixWidth => stampWidth + stampGap;

  static double maxBubbleWidth(double viewportWidth) =>
      viewportWidth.clamp(0, maxCap) * maxFraction;

  static StampLayout measure({
    required String text,
    required String stamp,
    required double viewportWidth,
    bool grouped = false,
    TextStyle? textStyle,
    TextStyle? stampStyle,
    double checksWidth = 0,
    double headerHeight = 0,
  }) {
    final maxBubble = maxBubbleWidth(viewportWidth);
    final tailInset = grouped ? 0.0 : tail;
    final inner = maxBubble - padLeft - padRight - tailInset;
    final stampPainter = TextPainter(
      text: TextSpan(text: stamp, style: stampStyle ?? StampLayout.stampStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final stampW = stampPainter.width + checksWidth;
    final stampH = stampPainter.height;
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle ?? StampLayout.textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: inner);
    final metrics = textPainter.computeLineMetrics();
    final last = metrics.isEmpty ? 0.0 : metrics.last.width;
    final fits = last + stampGap + stampW <= inner + 0.5;
    final innerWidth = fits
        ? (textPainter.width < last + stampGap + stampW
              ? last + stampGap + stampW
              : textPainter.width)
        : (textPainter.width < stampW ? stampW : textPainter.width);
    final innerHeight = fits
        ? (textPainter.height < stampH ? stampH : textPainter.height)
        : textPainter.height + 2 + stampH;
    return StampLayout(
      bubbleWidth: innerWidth + padLeft + padRight + tailInset,
      bubbleHeight: innerHeight + padTop + padBottom + headerHeight,
      innerWidth: inner,
      stampWidth: stampW,
      stampHeight: stampH,
      sameLine: fits,
    );
  }
}

bool usesNativeTextCell(Map<String, dynamic> message) {
  if (message['deleted'] == true) return false;
  if (message['kind'] != 'text') return false;
  final media = message['media_id']?.toString() ?? '';
  if (media.isNotEmpty) return false;
  final markup = message['reply_markup'];
  if (markup is Map && markup.isNotEmpty) return false;
  return true;
}

bool hasReplyQuote(Map<String, dynamic> message) {
  final raw = message['reply_to'];
  if (raw is! String) return false;
  final reply = raw.trim();
  return reply.isNotEmpty && reply != '0' && reply != 'null';
}
