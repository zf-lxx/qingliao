import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/motion/tg_curves.dart';
import '../ui/theme/tg_tokens.dart';

/// Reply swipe aligned to DrKLO/Telegram ChatActivity (read 2026-11-11):
/// left swipe, clamp -80dp, start after 0.4cm with |dx|/3 > dy, haptic at 50dp
/// once, snap 180ms Android Decelerate(1). Independent Dart, no Java copied.
class SwipeReply extends StatefulWidget {
  static const maxPull = 80.0;
  static const trigger = 50.0;
  static const arrowAppear = 20.0;
  static const startCm = 0.4;
  final bool enabled;
  final bool outgoing;
  final VoidCallback onReply;
  final VoidCallback? onLongPress;
  final Widget child;
  const SwipeReply({
    super.key,
    required this.enabled,
    required this.onReply,
    this.onLongPress,
    this.outgoing = false,
    required this.child,
  });
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply>
    with SingleTickerProviderStateMixin {
  double _dx = 0, _startX = 0, _startY = 0;
  bool _tracking = false, _maybe = false, _vibrated = false;
  late final AnimationController _snap = AnimationController.unbounded(
    vsync: this,
  );

  double get _dpi => MediaQuery.devicePixelRatioOf(context) * 160;

  double get _startPx => (SwipeReply.startCm / 2.54) * _dpi;

  @override
  void initState() {
    super.initState();
    _snap.addListener(() => setState(() => _dx = _snap.value));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _end({required bool commit}) {
    if (commit && _dx.abs() >= SwipeReply.trigger) widget.onReply();
    _tracking = false;
    _maybe = false;
    _vibrated = false;
    _snap.value = _dx;
    _snap
        .animateTo(
          0,
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 180,
          ),
          curve: const AndroidDecelerate(1),
        )
        .whenComplete(() {
          if (mounted) setState(() => _dx = 0);
        });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final iconProgress = ((_dx.abs() - SwipeReply.arrowAppear) / 30).clamp(
      0.0,
      1.0,
    );
    final fill = (_dx.abs() / SwipeReply.trigger).clamp(0.0, 1.0);
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragStart: widget.enabled
          ? (d) {
              if (_snap.isAnimating) _snap.stop();
              _maybe = true;
              _tracking = false;
              _vibrated = false;
              _startX = d.globalPosition.dx;
              _startY = d.globalPosition.dy;
              setState(() => _dx = 0);
            }
          : null,
      onHorizontalDragUpdate: widget.enabled
          ? (d) {
              final rawX = d.globalPosition.dx - _startX;
              final rawY = (d.globalPosition.dy - _startY).abs();
              if (_maybe && !_tracking) {
                if (rawX <= -_startPx && rawX.abs() / 3 > rawY) {
                  _tracking = true;
                  _maybe = false;
                  _startX = d.globalPosition.dx;
                } else if (rawX.abs() > 24 && rawY > rawX.abs() / 3) {
                  _maybe = false;
                }
                return;
              }
              if (!_tracking) return;
              final next = math.max(-SwipeReply.maxPull, math.min(0.0, rawX));
              setState(() => _dx = next);
              if (next.abs() >= SwipeReply.trigger) {
                if (!_vibrated) {
                  _vibrated = true;
                  HapticFeedback.selectionClick();
                }
              } else {
                _vibrated = false;
              }
            }
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) => _end(commit: _tracking)
          : null,
      onHorizontalDragCancel: widget.enabled ? () => _end(commit: false) : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (iconProgress > 0 && !reduce)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ReplyArrowPainter(
                    offset: _dx,
                    progress: iconProgress,
                    fill: fill,
                    outgoing: widget.outgoing,
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

class _ReplyArrowPainter extends CustomPainter {
  final double offset, progress, fill;
  final bool outgoing;
  const _ReplyArrowPainter({
    required this.offset,
    required this.progress,
    required this.fill,
    required this.outgoing,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width + offset * (outgoing ? 0.5 : 1);
    final y = size.height / 2;
    final scale = progress;
    final r = 16.0 * scale;
    final rect = Rect.fromCircle(center: Offset(x, y), radius: r);
    final bg = Paint()
      ..color = TgTokens.raised.withValues(alpha: 0.6 * progress * fill);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), bg);
    final icon = Paint()
      ..color = Colors.white.withValues(alpha: progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path()
      ..moveTo(x + 3.5 * scale, y - 5.5 * scale)
      ..lineTo(x - 4 * scale, y)
      ..lineTo(x + 3.5 * scale, y + 5.5 * scale);
    canvas.drawPath(p, icon);
  }

  @override
  bool shouldRepaint(_ReplyArrowPainter old) =>
      offset != old.offset ||
      progress != old.progress ||
      fill != old.fill ||
      outgoing != old.outgoing;
}
