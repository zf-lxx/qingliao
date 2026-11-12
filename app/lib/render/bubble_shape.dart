import 'package:flutter/material.dart';

import 'bubble_path.dart';

/// [ShapeBorder] backed by [qingliaoBubblePath], for existing bubble backgrounds.
class QingliaoBubbleShape extends ShapeBorder {
  final bool mine, grouped, media;
  const QingliaoBubbleShape({
    required this.mine,
    this.grouped = false,
    this.media = false,
  });
  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(0);
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      qingliaoBubblePath(rect, mine: mine, grouped: grouped, media: media);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  @override
  ShapeBorder scale(double t) => this;
}
