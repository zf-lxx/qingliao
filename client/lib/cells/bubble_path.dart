import 'package:flutter/material.dart';

/// Independent bubble outline. Tail is part of the path, not a stacked triangle
/// widget. Grouped consecutive messages drop the tail and tighten one corner.
Path qingliaoBubblePath(Rect rect, {required bool mine, bool grouped = false}) {
  final inset = grouped ? 0.0 : 5.0;
  final r = Rect.fromLTRB(
    rect.left + (mine ? 0 : inset),
    rect.top,
    rect.right - (mine ? inset : 0),
    rect.bottom,
  );
  final body = Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        r,
        topLeft: const Radius.circular(17),
        topRight: const Radius.circular(17),
        bottomLeft: Radius.circular(!mine && grouped ? 5 : 17),
        bottomRight: Radius.circular(mine && grouped ? 5 : 17),
      ),
    );
  if (grouped) return body;
  final tail = Path();
  if (mine) {
    tail.moveTo(r.right - 11, r.bottom - 12);
    tail.quadraticBezierTo(r.right - 2, r.bottom - 3, rect.right, r.bottom);
    tail.lineTo(r.right - 16, r.bottom);
  } else {
    tail.moveTo(r.left + 11, r.bottom - 12);
    tail.quadraticBezierTo(r.left + 2, r.bottom - 3, rect.left, r.bottom);
    tail.lineTo(r.left + 16, r.bottom);
  }
  tail.close();
  return Path.combine(PathOperation.union, body, tail);
}

class QingliaoBubblePainter extends CustomPainter {
  final bool mine, grouped;
  final Color color;
  const QingliaoBubblePainter({
    required this.mine,
    required this.grouped,
    required this.color,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      qingliaoBubblePath(Offset.zero & size, mine: mine, grouped: grouped),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(QingliaoBubblePainter old) =>
      mine != old.mine || grouped != old.grouped || color != old.color;
}
