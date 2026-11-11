import 'package:flutter/material.dart';

import '../cells/bubble_path.dart';
import '../cells/message_layout.dart';
import '../ui/motion/tg_motion.dart';
import '../ui/theme/tg_tokens.dart';

const composerTextSize = 16.0;

class MessageEnterFlight {
  final String id, text, stamp;
  final Rect from, to;
  final double fromTextSize;
  const MessageEnterFlight({
    required this.id,
    required this.text,
    required this.stamp,
    required this.from,
    required this.to,
    this.fromTextSize = composerTextSize,
  });
}

/// Overlay aligned to TextMessageEnterTransition progress mapping
/// (linear animator, Y=message curve, X=EASE_OUT(QuINT), alpha to 0.4).
/// Text starts at the composer size and scales to bubble 15sp (scaleFrom).
class MessageEnterLayer extends StatefulWidget {
  final MessageEnterFlight flight;
  final VoidCallback onDone;
  final Duration duration;
  final Curve curve;
  const MessageEnterLayer({
    super.key,
    required this.flight,
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
    final flight = widget.flight;
    final scaleFrom =
        flight.fromTextSize / (StampLayout.textStyle.fontSize ?? 15);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final linear = widget.curve.transform(_c.value);
        final yT = tgMessageCurve.transform(linear);
        final xT = tgEaseOut.transform(tgEaseOutQuint.transform(linear));
        final alpha = linear > 0.4 ? 1.0 : linear / 0.4;
        final rect = Rect.fromLTRB(
          flight.from.left + (flight.to.left - flight.from.left) * xT,
          flight.from.top + (flight.to.top - flight.from.top) * yT,
          flight.from.right + (flight.to.right - flight.from.right) * xT,
          flight.from.bottom + (flight.to.bottom - flight.from.bottom) * yT,
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
                        flight.text,
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

Rect composerTextRect({
  required Rect field,
  required String text,
  TextStyle? style,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style ?? const TextStyle(fontSize: composerTextSize, height: 1.45),
    ),
    maxLines: 5,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: (field.width - 10).clamp(24, 800));
  const padX = 5.0, padY = 13.0;
  return Rect.fromLTWH(
    field.left + padX,
    field.top + padY,
    painter.width.clamp(24, field.width),
    painter.height.clamp(20, field.height),
  );
}

class MessageEnterController {
  final List<MessageEnterFlight> flights = [];
  bool get active => flights.isNotEmpty;
  bool hides(String messageId) => flights.any((f) => f.id == messageId);

  void begin(MessageEnterFlight flight) {
    flights.removeWhere((f) => f.id == flight.id);
    flights.add(flight);
  }

  void complete(String id) {
    flights.removeWhere((f) => f.id == id);
  }
}

bool skipEnterAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
