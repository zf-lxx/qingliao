//
//  stable_system_insets.dart
//
//  A newly pushed route sometimes reports a 0 safe-area inset for a frame or
//  two, then the real status-bar or gesture-bar height arrives. If a header or
//  the composer follows that 0, the transcript is squeezed and looks like it
//  lifts once above the composer. Remember the last real inset and ignore a
//  brief zero; a value that stays 0 (landscape, no gesture bar) is accepted
//  after a few frames so rotation is not stuck on the old padding.
//
//  A route transition can report 0 for much longer than a couple of frames.
//  Counting those zeros would clear the cache mid-push, then the real inset
//  would grow the composer and lift the transcript. Zeros during a transition
//  are ignored, and a settled zero still takes more than a short fade to
//  accept.
//

import 'package:flutter/widgets.dart';

/// How many consecutive zero readings may be ignored before the inset is
/// allowed to fall back to 0, once the route is no longer transitioning.
const int kTransientZeroInsetFrames = 24;

/// Process-wide last-known system view paddings, with a short hold against
/// transient zeros on a newly pushed route.
class StableSystemInsets {
  StableSystemInsets._();

  static double _top = 0;
  static double _bottom = 0;
  static int _zeroTopFrames = 0;
  static int _zeroBottomFrames = 0;
  static bool _observingViews = false;

  /// Last positive top inset, or 0 if none has been seen.
  static double get lastTop => _top;

  /// Last positive bottom inset, or 0 if none has been seen.
  static double get lastBottom => _bottom;

  /// Record paddings from the current view so a later route does not start
  /// from zero. The tab shell should call this while it is on screen.
  static void observeFrom(BuildContext context) {
    ensureObserved();
    holdTop(measureTop(context));
    holdBottom(measureBottom(context));
  }

  /// Top view padding, holding through a brief zero.
  static double topOf(BuildContext context) => holdTop(
    measureTop(context),
    ignoreTransientZero: isRouteTransitioning(context),
  );

  /// Bottom view padding, holding through a brief zero.
  static double bottomOf(BuildContext context) => holdBottom(
    measureBottom(context),
    ignoreTransientZero: isRouteTransitioning(context),
  );

  /// Whether [context]'s route is still animating in or out.
  static bool isRouteTransitioning(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return false;
    bool running(Animation<double>? animation) =>
        animation != null &&
        (animation.status == AnimationStatus.forward ||
            animation.status == AnimationStatus.reverse);
    return running(route.animation) || running(route.secondaryAnimation);
  }

  /// Prefer the FlutterView's view padding when MediaQuery has not caught up.
  static double measureTop(BuildContext context) {
    ensureObserved();
    final view = View.of(context);
    final fromView = view.viewPadding.top / view.devicePixelRatio;
    final fromMedia = MediaQuery.viewPaddingOf(context).top;
    return _greaterFinite(fromView, fromMedia);
  }

  /// Prefer the FlutterView's view padding when MediaQuery has not caught up.
  static double measureBottom(BuildContext context) {
    ensureObserved();
    final view = View.of(context);
    final fromView = view.viewPadding.bottom / view.devicePixelRatio;
    final fromMedia = MediaQuery.viewPaddingOf(context).bottom;
    return _greaterFinite(fromView, fromMedia);
  }

  /// Keep [reported] unless it is a short-lived zero after a real inset.
  static double holdTop(double reported, {bool ignoreTransientZero = false}) =>
      _hold(reported, isTop: true, ignoreTransientZero: ignoreTransientZero);

  /// Keep [reported] unless it is a short-lived zero after a real inset.
  static double holdBottom(
    double reported, {
    bool ignoreTransientZero = false,
  }) => _hold(reported, isTop: false, ignoreTransientZero: ignoreTransientZero);

  /// Seed the cache from every attached view's current padding. Only positive
  /// values are recorded, so a 0 on a different view cannot wipe the cache.
  static void ensureObserved() {
    if (_observingViews) return;
    _observingViews = true;
    WidgetsBinding.instance.addObserver(_InsetsBindingObserver());
    _observePositiveViewInsets();
  }

  static void _observePositiveViewInsets() {
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      final dpr = view.devicePixelRatio;
      if (dpr <= 0) continue;
      final top = view.viewPadding.top / dpr;
      final bottom = view.viewPadding.bottom / dpr;
      if (top.isFinite && top > 0) holdTop(top);
      if (bottom.isFinite && bottom > 0) holdBottom(bottom);
    }
  }

  static double _hold(
    double reported, {
    required bool isTop,
    bool ignoreTransientZero = false,
  }) {
    final value = reported.isFinite && reported > 0 ? reported : 0.0;
    if (value > 0) {
      if (isTop) {
        _top = value;
        _zeroTopFrames = 0;
      } else {
        _bottom = value;
        _zeroBottomFrames = 0;
      }
      return value;
    }
    final last = isTop ? _top : _bottom;
    if (last <= 0) return 0;
    if (ignoreTransientZero) return last;
    final frames = isTop ? ++_zeroTopFrames : ++_zeroBottomFrames;
    if (frames <= kTransientZeroInsetFrames) return last;
    if (isTop) {
      _top = 0;
    } else {
      _bottom = 0;
    }
    return 0;
  }

  static double _greaterFinite(double a, double b) {
    final aOk = a.isFinite && a > 0;
    final bOk = b.isFinite && b > 0;
    if (aOk && bOk) return a > b ? a : b;
    if (aOk) return a;
    if (bOk) return b;
    return 0;
  }

  @visibleForTesting
  static void debugReset() {
    _top = 0;
    _bottom = 0;
    _zeroTopFrames = 0;
    _zeroBottomFrames = 0;
  }
}

class _InsetsBindingObserver with WidgetsBindingObserver {
  @override
  void didChangeMetrics() {
    StableSystemInsets.ensureObserved();
  }
}
