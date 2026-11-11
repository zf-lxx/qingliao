import 'package:flutter/material.dart';

import '../cells/bubble_path.dart';
import '../cells/message_layout.dart';
import '../ui/motion/tg_motion.dart';
import '../ui/theme/tg_tokens.dart';

const composerTextSize = 16.0;

/// Overlay aligned to TextMessageEnterTransition progress mapping
/// (linear animator, Y=message curve, X=EASE_OUT(QuINT), alpha to 0.4).
/// Text starts at the composer size and scales to bubble 15sp (scaleFrom).
class MessageEnterLayer extends StatefulWidget {
  final String text, stamp;
  final Rect from, to;
  final double fromTextSize;
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
    this.fromTextSize = composerTextSize,
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
    final scaleFrom =
        widget.fromTextSize / (StampLayout.textStyle.fontSize ?? 15);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final linear = widget.curve.transform(_c.value);
        final yT = tgMessageCurve.transform(linear);
        final xT = tgEaseOut.transform(tgEaseOutQuint.transform(linear));
        final alpha = linear > 0.4 ? 1.0 : linear / 0.4;
        final rect = Rect.fromLTRB(
          widget.from.left + (widget.to.left - widget.from.left) * xT,
          widget.from.top + (widget.to.top - widget.from.top) * yT,
          widget.from.right + (widget.to.right - widget.from.right) * xT,
          widget.from.bottom + (widget.to.bottom - widget.from.bottom) * yT,
        );
        final scale = scaleFrom + (1 - scaleFrom) * yT;
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: Opacity(
              opacity: alpha,
              child: CustomPaint(
                painter: _EnterPainter(progress: yT),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    StampLayout.padLeft,
                    StampLayout.padTop,
                    StampLayout.padRight + StampLayout.tail,
                    StampLayout.padBottom,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: scale,
                      child: Text(
                        widget.text,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: StampLayout.textStyle.copyWith(
                          color: Color.lerp(
                            TgTokens.muted,
                            const Color(0xffeef4fa),
                            yT,
                          ),
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
  final double progress;
  const _EnterPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final color = Color.lerp(
      const Color(0xff22303d),
      const Color(0xff24445e),
      progress,
    )!;
    canvas.drawPath(
      qingliaoBubblePath(
        Offset.zero & size,
        mine: true,
        grouped: progress < .55,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_EnterPainter old) => progress != old.progress;
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

class MessageEnterController {
  String? id;
  Rect? from, to;
  String text = '', stamp = '';
  double fromTextSize = composerTextSize;
  bool get active => id != null;
  bool hides(String messageId) => id == messageId;
  void begin({
    required String id,
    required String text,
    required String stamp,
    required Rect from,
    required Rect to,
    double fromTextSize = composerTextSize,
  }) {
    this.id = id;
    this.text = text;
    this.stamp = stamp;
    this.from = from;
    this.to = to;
    this.fromTextSize = fromTextSize;
  }

  void complete() {
    id = null;
    from = null;
    to = null;
    text = '';
    stamp = '';
    fromTextSize = composerTextSize;
  }
}

bool skipEnterAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
