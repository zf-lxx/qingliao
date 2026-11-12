import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Independently implemented motion curves (parameters only).
const qlDefaultCurve = Cubic(.25, .1, .25, 1);
const qlEaseOut = Cubic(0, 0, .58, 1);
const qlEaseIn = Cubic(.42, 0, 1, 1);
const qlEaseOutQuint = Cubic(.23, 1, .32, 1);
const qlMessageCurve = Cubic(
  .19919472913616398,
  .01064453125,
  .27920937042459737,
  .91025390625,
);
const qlAndroidDefaultCurve = AndroidAccelerateDecelerate();
const qlPhotoMoveCurve = AndroidDecelerate(1.5);

class AndroidAccelerateDecelerate extends Curve {
  const AndroidAccelerateDecelerate();
  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2 + .5;
}

class AndroidDecelerate extends Curve {
  final double factor;
  const AndroidDecelerate(this.factor);
  @override
  double transformInternal(double t) =>
      1 - math.pow(1 - t, 2 * factor).toDouble();
}

class QlOvershoot extends Curve {
  final double tension;
  const QlOvershoot([this.tension = 1.5]);
  @override
  double transformInternal(double t) {
    t -= 1;
    return t * t * ((tension + 1) * t + tension) + 1;
  }
}

abstract final class QlDuration {
  static const press = Duration(milliseconds: 80);
  static const release = Duration(milliseconds: 350);
  static const page = Duration(milliseconds: 200);
  static const title = Duration(milliseconds: 220);
  static const item = Duration(milliseconds: 180);
  static const message = Duration(milliseconds: 250);
  static const swipeSnap = Duration(milliseconds: 180);
  static const popupDismiss = Duration(milliseconds: 150);
  static const sheetOpen = Duration(milliseconds: 400);
  static const sheetClose = Duration(milliseconds: 250);
}

/// Finish / cancel durations for a finger-driven back gesture.
Duration qlBackFinishDuration(double remaining, double width) {
  if (width <= 0) return const Duration(milliseconds: 50);
  return Duration(
    milliseconds: math.max(50, (200 * remaining / width).round()),
  );
}

Duration qlBackCancelDuration(double traveled, double width) {
  if (width <= 0) return const Duration(milliseconds: 120);
  return Duration(
    milliseconds: math.max(120, (320 * traveled / width).round()),
  );
}

/// Scrim alpha while a page covers the one underneath.
double qlBackScrimOpacity(double coveredFraction) {
  final cover = coveredFraction.clamp(0.0, 0.8);
  return (120 / 255) * cover;
}

/// Predictive-back scale of the moving page.
double qlBackPageScale(double translationX) {
  final shrink = 0.05 * translationX / 56.0;
  return 1 - (shrink > 0.25 ? 0.25 : shrink);
}

/// Edge start distance: 0.4 cm in logical pixels.
double qlEdgeStartPx(double devicePixelRatio) =>
    (0.4 / 2.54) * devicePixelRatio * 160;
