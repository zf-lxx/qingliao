import 'package:flutter/material.dart';

import 'bubble_path.dart';
import 'message_layout.dart';
import 'ql_curves.dart';

const composerTextSize = 16.0;

class MessageEnterFlight {
  final String id, text, stamp;
  final Rect from, to;
  final double fromTextSize;
  final Color fromColor, toColor, fromTextColor, toTextColor;
  const MessageEnterFlight({
    required this.id,
    required this.text,
    required this.stamp,
    required this.from,
    required this.to,
    this.fromTextSize = composerTextSize,
    this.fromColor = const Color(0xff22303d),
    this.toColor = const Color(0xff24445e),
    this.fromTextColor = const Color(0xff8a9aab),
    this.toTextColor = const Color(0xffeef4fa),
  });
}

/// Overlay that interpolates composer typography/rect into the outgoing bubble.
/// Concurrent flights are allowed; each id animates independently.
class MessageEnterLayer extends StatefulWidget {
  final MessageEnterFlight flight;
  final VoidCallback onDone;
  final Duration duration;
  final Curve curve;
  const MessageEnterLayer({
    super.key,
    required this.flight,
    required this.onDone,
    this.duration = QlDuration.message,
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
        final yT = qlMessageCurve.transform(linear);
        final xT = qlEaseOut.transform(qlEaseOutQuint.transform(linear));
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
                painter: _EnterPainter(
                  progress: yT,
                  fromColor: flight.fromColor,
                  toColor: flight.toColor,
                ),
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
                            flight.fromTextColor,
                            flight.toTextColor,
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
  final Color fromColor, toColor;
  const _EnterPainter({
    required this.progress,
    required this.fromColor,
    required this.toColor,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final color = Color.lerp(fromColor, toColor, progress)!;
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
  bool shouldRepaint(_EnterPainter old) =>
      progress != old.progress ||
      fromColor != old.fromColor ||
      toColor != old.toColor;
}

Rect estimateOutgoingRect({
  required Size viewport,
  required String text,
  required String stamp,
  required double composerTop,
  TextStyle? textStyle,
  TextStyle? stampStyle,
}) {
  final layout = StampLayout.measure(
    text: text,
    stamp: stamp,
    viewportWidth: viewport.width,
    textStyle: textStyle,
    stampStyle: stampStyle,
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

Rect? globalRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class MessageEnterController extends ChangeNotifier {
  final List<MessageEnterFlight> flights = [];
  final Map<String, String> _boundIds = {};
  bool get active => flights.isNotEmpty;
  bool hides(String messageId) =>
      flights.any((f) => f.id == messageId) ||
      _boundIds.values.contains(messageId);

  void begin(MessageEnterFlight flight) {
    flights.removeWhere((f) => f.id == flight.id);
    flights.add(flight);
    notifyListeners();
  }

  /// Hide the real list row while a pending flight (started before the
  /// message id was known) is still in the air.
  void bind(String pendingId, String realId) {
    if (_boundIds[pendingId] == realId) return;
    _boundIds[pendingId] = realId;
    notifyListeners();
  }

  void complete(String id) {
    final before = flights.length;
    flights.removeWhere((f) => f.id == id);
    _boundIds.remove(id);
    if (flights.length != before) notifyListeners();
  }
}

bool skipEnterAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
