import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Outline aligned to MessageDrawable.generatePath (DrKLO/Telegram, read
/// 2026-11-11). Independent Dart; no Java copied.
///
/// Text type: rad 17, near/small 6, padding 2, side inset 8, 83° tail arc.
/// Media type: same radii, side uses padding (no 8dp inset, no 83° tail).
const bubbleRadius = 17.0;
const nearRadius = 6.0;
const bubblePadding = 2.0;
const tailInset = 8.0;

Path qingliaoBubblePath(
  Rect bounds, {
  required bool mine,
  bool grouped = false,
  bool media = false,
}) {
  final pad = bubblePadding;
  var rad = bubbleRadius;
  final half = (bounds.height - pad) / 2;
  if (rad > half && half > 0) rad = half;
  final bottomRad = grouped ? nearRadius : rad;
  final side = media ? pad : tailInset;
  final roundTail = grouped || media;
  final path = Path();
  if (mine) {
    if (roundTail) {
      path.moveTo(bounds.right - side - bottomRad, bounds.bottom - pad);
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
    path.lineTo(bounds.right - side - rad, bounds.top + pad);
    _arc(
      path,
      bounds.right - side - rad * 2,
      bounds.top + pad,
      rad * 2,
      rad * 2,
      270,
      90,
    );
    if (roundTail) {
      path.lineTo(bounds.right - side, bounds.bottom - pad - bottomRad);
      _arc(
        path,
        bounds.right - side - bottomRad * 2,
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
    if (roundTail) {
      path.moveTo(bounds.left + side + bottomRad, bounds.bottom - pad);
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
    path.lineTo(bounds.left + side + rad, bounds.top + pad);
    _arc(
      path,
      bounds.left + side,
      bounds.top + pad,
      rad * 2,
      rad * 2,
      270,
      -90,
    );
    if (roundTail) {
      path.lineTo(bounds.left + side, bounds.bottom - pad - bottomRad);
      _arc(
        path,
        bounds.left + side,
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
  final bool mine, grouped, media;
  final Color color;
  const QingliaoBubblePainter({
    required this.mine,
    required this.grouped,
    required this.color,
    this.media = false,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      qingliaoBubblePath(
        Offset.zero & size,
        mine: mine,
        grouped: grouped,
        media: media,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(QingliaoBubblePainter old) =>
      mine != old.mine ||
      grouped != old.grouped ||
      media != old.media ||
      color != old.color;
}
