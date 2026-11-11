import 'package:flutter/material.dart';

import '../cells/bubble_path.dart';
import '../cells/message_layout.dart';
import '../ui/motion/tg_motion.dart';
import '../ui/theme/tg_tokens.dart';

/// Overlay that interpolates the composer field into the outgoing bubble rect.
/// Independent implementation; not a port of Telegram Java.
class MessageEnterLayer extends StatefulWidget {
  final String text, stamp;
  final Rect from, to;
  final Duration duration;
  final Curve curve;
  final VoidCallback onDone;
  const MessageEnterLayer({
    super.key,
    required this.text,
    required this.stamp,
    required this.from,
    required this.to,
    required this.onDone,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.linear,
  });
  @override
  State<MessageEnterLayer> createState() => _MessageEnterLayerState();
}

class _MessageEnterLayerState extends State<MessageEnterLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final linear = widget.curve.transform(_c.value);
        final t = tgMessageCurve.transform(linear);
        final rect = Rect.lerp(widget.from, widget.to, t)!;
        final radius = 17.0 + (4.0 * (1 - t));
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.35 + 0.65 * t,
              child: CustomPaint(
                painter: _EnterPainter(progress: t, radius: radius),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    StampLayout.padLeft,
                    StampLayout.padTop,
                    StampLayout.padRight + StampLayout.tail,
                    StampLayout.padBottom,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.text,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: StampLayout.textStyle.copyWith(
                        color: Color.lerp(
                          TgTokens.muted,
                          const Color(0xffeef4fa),
                          t,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EnterPainter extends CustomPainter {
  final double progress, radius;
  const _EnterPainter({required this.progress, required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    final color = Color.lerp(
      const Color(0xff22303d),
      const Color(0xff24445e),
      progress,
    )!;
    if (progress < .55) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        Paint()..color = color,
      );
      return;
    }
    canvas.drawPath(
      qingliaoBubblePath(Offset.zero & size, mine: true, grouped: false),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_EnterPainter old) =>
      progress != old.progress || radius != old.radius;
}

Rect estimateOutgoingRect({
  required Size viewport,
  required EdgeInsets viewPadding,
  required String text,
  required String stamp,
  required double composerTop,
}) {
  final layout = StampLayout.measure(
    text: text,
    stamp: stamp,
    viewportWidth: viewport.width,
  );
  final right = viewport.width - 10;
  final bottom = composerTop - 8;
  return Rect.fromLTWH(
    right - layout.bubbleWidth,
    bottom - layout.bubbleHeight,
    layout.bubbleWidth,
    layout.bubbleHeight,
  );
}

/// Keeps one outgoing enter animation at a time per chat page.
class MessageEnterController {
  String? id;
  Rect? from, to;
  String text = '', stamp = '';
  bool get active => id != null;
  bool hides(String messageId) => id == messageId;
  void begin({
    required String id,
    required String text,
    required String stamp,
    required Rect from,
    required Rect to,
  }) {
    this.id = id;
    this.text = text;
    this.stamp = stamp;
    this.from = from;
    this.to = to;
  }

  void complete() {
    id = null;
    from = null;
    to = null;
    text = '';
    stamp = '';
  }
}

bool skipEnterAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
