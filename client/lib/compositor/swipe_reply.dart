import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/motion/tg_motion.dart';

/// Horizontal reply gesture: linear to the trigger, then rubber-banded.
/// Crossing the trigger fires haptics once. Release always snaps back.
class SwipeReply extends StatefulWidget {
  static const trigger = 48.0, maxPull = 78.0;
  final bool enabled;
  final VoidCallback onReply;
  final VoidCallback? onLongPress;
  final Widget child;
  const SwipeReply({
    super.key,
    required this.enabled,
    required this.onReply,
    this.onLongPress,
    required this.child,
  });
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply>
    with SingleTickerProviderStateMixin {
  double _raw = 0;
  bool _fired = false;
  late final AnimationController _snap = AnimationController.unbounded(
    vsync: this,
  );

  static double damped(double raw) {
    if (raw <= 0) return 0;
    if (raw <= SwipeReply.trigger) return raw;
    final extra = (raw - SwipeReply.trigger) * .35;
    final y = SwipeReply.trigger + extra;
    return y > SwipeReply.maxPull ? SwipeReply.maxPull : y;
  }

  @override
  void initState() {
    super.initState();
    _snap.addListener(() => setState(() => _raw = _snap.value));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _end() {
    if (damped(_raw) >= SwipeReply.trigger) {
      widget.onReply();
    }
    _fired = false;
    _snap.value = _raw;
    _snap
        .animateTo(
          0,
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 180,
          ),
          curve: tgEaseOutQuint,
        )
        .whenComplete(() {
          if (mounted) setState(() => _raw = 0);
        });
  }

  @override
  Widget build(BuildContext context) {
    final dx = damped(_raw);
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: widget.enabled
          ? (d) {
              if (_snap.isAnimating) _snap.stop();
              final next = (_raw + d.delta.dx).clamp(0.0, 220.0);
              setState(() => _raw = next);
              if (!_fired && damped(next) >= SwipeReply.trigger) {
                _fired = true;
                HapticFeedback.selectionClick();
              }
            }
          : null,
      onHorizontalDragEnd: widget.enabled ? (_) => _end() : null,
      onHorizontalDragCancel: widget.enabled ? _end : null,
      child: Transform.translate(offset: Offset(dx, 0), child: widget.child),
    );
  }
}
