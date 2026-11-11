import 'package:flutter/material.dart';

/// When a new message is inserted at the bottom, previous rows start from their
/// old Y and ease to the new layout position. Independent of Telegram source.
class InsertShift extends StatelessWidget {
  final int generation;
  final double amount;
  final bool enabled;
  final Widget child;
  const InsertShift({
    super.key,
    required this.generation,
    required this.amount,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || generation <= 0) return child;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey(generation),
      duration: Duration(milliseconds: reduce ? 1 : 250),
      curve: const Cubic(
        .19919472913616398,
        .01064453125,
        .27920937042459737,
        .91025390625,
      ),
      tween: Tween(begin: reduce ? 0 : amount, end: 0),
      builder: (context, y, child) =>
          Transform.translate(offset: Offset(0, y), child: child),
      child: child,
    );
  }
}
