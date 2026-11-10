import 'dart:math' as math;

import 'package:flutter/animation.dart';

// Parameters only, independently implemented. No Telegram source/assets copied.
const tgDefaultCurve = Cubic(.25, .1, .25, 1);
const tgAndroidDefaultCurve = AndroidAccelerateDecelerate();
const tgPhotoMoveCurve = AndroidDecelerate(1.5);

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
