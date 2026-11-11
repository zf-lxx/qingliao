import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text-bubble outline aligned to MessageDrawable.generatePath for TYPE text
/// (DrKLO/Telegram, 2026-11-11 read). Independent Dart; no Java copied.
///
/// rad = bubbleRadius 17; near/small = 6; padding = 2; tail inset = 8.
/// Tail is an 83° arc, not a triangle. Grouped messages drop the tail and
/// use 6dp on the bottom corner of the tail side.
const bubbleRadius = 17.0;
const nearRadius = 6.0;
const bubblePadding = 2.0;
const tailInset = 8.0;

Path qingliaoBubblePath(
  Rect bounds, {
  required bool mine,
  bool grouped = false,
}) {
  final pad = bubblePadding;
  var rad = bubbleRadius;
  final half = (bounds.height - pad) / 2;
  if (rad > half && half > 0) rad = half;
  final bottomRad = grouped ? nearRadius : rad;
  final topTailRad = rad;
  final path = Path();
  if (mine) {
    if (grouped) {
      path.moveTo(bounds.right - pad - bottomRad, bounds.bottom - pad);
    } else {
      path.moveTo(bounds.right - 2.6, bounds.bottom - pad);
    }
    path.lineTo(bounds.left + pad + bottomRad, bounds.bottom - pad);
    _arc(
      path,
      bounds.left + pad,
      bounds.bottom - pad - bottomRad * 2,
      bottomRad * 2,
      bottomRad * 2,
      90,
      90,
    );
    path.lineTo(bounds.left + pad, bounds.top + pad + rad);
    _arc(path, bounds.left + pad, bounds.top + pad, rad * 2, rad * 2, 180, 90);
    path.lineTo(bounds.right - tailInset - topTailRad, bounds.top + pad);
    _arc(
      path,
      bounds.right - tailInset - topTailRad * 2,
      bounds.top + pad,
      topTailRad * 2,
      topTailRad * 2,
      270,
      90,
    );
    if (grouped) {
      path.lineTo(bounds.right - pad, bounds.bottom - pad - bottomRad);
      _arc(
        path,
        bounds.right - pad - bottomRad * 2,
        bounds.bottom - pad - bottomRad * 2,
        bottomRad * 2,
        bottomRad * 2,
        0,
        90,
      );
    } else {
      path.lineTo(
        bounds.right - tailInset,
        bounds.bottom - pad - nearRadius - 3,
      );
      _arc(
        path,
        bounds.right - tailInset,
        bounds.bottom - pad - nearRadius * 2 - 9,
        nearRadius * 2 + 1,
        nearRadius * 2 + 8,
        180,
        -83,
      );
    }
  } else {
    if (grouped) {
      path.moveTo(bounds.left + pad + bottomRad, bounds.bottom - pad);
    } else {
      path.moveTo(bounds.left + 2.6, bounds.bottom - pad);
    }
    path.lineTo(bounds.right - pad - bottomRad, bounds.bottom - pad);
    _arc(
      path,
      bounds.right - pad - bottomRad * 2,
      bounds.bottom - pad - bottomRad * 2,
      bottomRad * 2,
      bottomRad * 2,
      90,
      -90,
    );
    path.lineTo(bounds.right - pad, bounds.top + pad + rad);
    _arc(
      path,
      bounds.right - pad - rad * 2,
      bounds.top + pad,
      rad * 2,
      rad * 2,
      0,
      -90,
    );
    path.lineTo(bounds.left + tailInset + topTailRad, bounds.top + pad);
    _arc(
      path,
      bounds.left + tailInset,
      bounds.top + pad,
      topTailRad * 2,
      topTailRad * 2,
      270,
      -90,
    );
    if (grouped) {
      path.lineTo(bounds.left + pad, bounds.bottom - pad - bottomRad);
      _arc(
        path,
        bounds.left + pad,
        bounds.bottom - pad - bottomRad * 2,
        bottomRad * 2,
        bottomRad * 2,
        180,
        -90,
      );
    } else {
      path.lineTo(
        bounds.left + tailInset,
        bounds.bottom - pad - nearRadius - 3,
      );
      _arc(
        path,
        bounds.left + 7 - nearRadius * 2,
        bounds.bottom - pad - nearRadius * 2 - 9,
        nearRadius * 2 + 1,
        nearRadius * 2 + 8,
        0,
        83,
      );
    }
  }
  path.close();
  return path;
}

void _arc(
  Path path,
  double left,
  double top,
  double width,
  double height,
  double startDeg,
  double sweepDeg,
) {
  path.arcTo(
    Rect.fromLTWH(left, top, width, height),
    startDeg * math.pi / 180,
    sweepDeg * math.pi / 180,
    false,
  );
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
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(QingliaoBubblePainter old) =>
      mine != old.mine || grouped != old.grouped || color != old.color;
}
