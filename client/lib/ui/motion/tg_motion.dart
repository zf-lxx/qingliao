import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'tg_curves.dart';
export 'tg_curves.dart';

abstract final class TgDuration {
  static const press = Duration(milliseconds: 80);
  static const release = Duration(milliseconds: 350);
  static const page = Duration(milliseconds: 200);
  static const title = Duration(milliseconds: 220);
  static const item = Duration(milliseconds: 180);
  static const message = Duration(milliseconds: 250);
  static const popupDismiss = Duration(milliseconds: 150);
  static const sheetOpen = Duration(milliseconds: 400);
  static const sheetClose = Duration(milliseconds: 250);
}

const tgEaseOutQuint = Cubic(.23, 1, .32, 1);
const tgMessageCurve = Cubic(
  .19919472913616398,
  .01064453125,
  .27920937042459737,
  .91025390625,
);

class TgOvershoot extends Curve {
  final double tension;
  const TgOvershoot([this.tension = 1.5]);
  @override
  double transformInternal(double t) {
    t -= 1;
    return t * t * ((tension + 1) * t + tension) + 1;
  }
}

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale, radius;
  final String? tooltip;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = .96,
    this.radius = 100,
    this.tooltip,
  });
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    duration: TgDuration.press,
  );
  @override
  void initState() {
    super.initState();
    _press.addListener(() => setState(() {}));
  }

  void _down(bool down) {
    _press.stop();
    _press.duration = down ? TgDuration.press : TgDuration.release;
    _press.animateTo(
      down ? 1 : 0,
      curve: down ? tgAndroidDefaultCurve : const TgOvershoot(),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget result = Transform.scale(
      scale: reduce ? 1 : 1 - (1 - widget.pressedScale) * _press.value,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          splashFactory: InkRipple.splashFactory,
          splashColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: .08),
          highlightColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: .04),
          child: widget.child,
        ),
      ),
    );
    result = Listener(
      onPointerDown: widget.onTap == null ? null : (_) => _down(true),
      onPointerUp: (_) => _down(false),
      onPointerCancel: (_) => _down(false),
      child: result,
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

class TgIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color, background;
  final double size;
  const TgIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = 46,
  });
  @override
  Widget build(BuildContext context) => PressableScale(
    tooltip: tooltip,
    onTap: onPressed,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(
        icon,
        size: 24,
        color: onPressed == null ? Colors.grey : color,
      ),
    ),
  );
}

/// Navigation aligned to ActionBarLayout classic swipe (not predictive-back).
/// Start after 0.4cm with |dx|/3 > dy. Finish unless x < width/3 AND
/// (velX < 3500 || |velX| < |velY|). Snap durations from animateBackEndAnimation.
class TgPageRoute<T> extends PageRoute<T> {
  final Widget page;
  final Duration duration;
  final Curve curve;
  bool _dragging = false, _maybe = false;
  double _startX = 0, _startY = 0;
  TgPageRoute({
    required this.page,
    super.settings,
    this.duration = TgDuration.page,
    this.curve = const AndroidDecelerate(1),
  });
  @override
  Duration get transitionDuration => duration;
  @override
  Duration get reverseTransitionDuration => duration;
  @override
  bool get opaque => false;
  @override
  bool get maintainState => true;
  @override
  bool get barrierDismissible => false;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page;
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final primary = _dragging
            ? animation.value
            : curve.transform(animation.value);
        final slide = 1 - primary;
        // Predictive-back scale from ActionBarLayout.drawChild (non-gesture
        // newBack branch): 1 - min(0.25, 0.05 * translationX / 56dp).
        final translationX = width * slide;
        final shrink = 0.05 * translationX / 56.0;
        final scale = 1 - (shrink > 0.25 ? 0.25 : shrink);
        // Edge shadow on the moving page, alpha = clamp(255 * covered/20dp, 0, 255).
        final shadowAlpha = (255 * (translationX / 20).clamp(0.0, 1.0) / 255);
        return Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(translationX, 0),
                child: Transform.scale(
                  alignment: Alignment.centerLeft,
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: shadowAlpha),
                          blurRadius: 12,
                          offset: const Offset(-6, 0),
                        ),
                      ],
                    ),
                    child: child!,
                  ),
                ),
              ),
            ),
            if (canPop && isCurrent)
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: (d) {
                    if (!isCurrent ||
                        animation.status != AnimationStatus.completed ||
                        popDisposition == RoutePopDisposition.doNotPop) {
                      return;
                    }
                    _maybe = true;
                    _dragging = false;
                    _startX = d.globalPosition.dx;
                    _startY = d.globalPosition.dy;
                  },
                  onHorizontalDragUpdate: (d) {
                    final dx = d.globalPosition.dx - _startX;
                    final dy = (d.globalPosition.dy - _startY).abs();
                    final startPx =
                        (0.4 / 2.54) *
                        MediaQuery.devicePixelRatioOf(context) *
                        160;
                    if (_maybe && !_dragging) {
                      if (dx >= startPx && dx.abs() / 3 > dy) {
                        _dragging = true;
                        _maybe = false;
                        controller!.stop();
                        navigator!.didStartUserGesture();
                      } else if (dx.abs() > 24 && dy > dx.abs() / 3) {
                        _maybe = false;
                        return;
                      } else {
                        return;
                      }
                    }
                    if (_dragging) {
                      controller!.value =
                          (1 - (d.globalPosition.dx - _startX) / width).clamp(
                            0.0,
                            1.0,
                          );
                    }
                  },
                  onHorizontalDragEnd: (d) => _finish(
                    d.velocity.pixelsPerSecond.dx,
                    d.velocity.pixelsPerSecond.dy,
                    width,
                  ),
                  onHorizontalDragCancel: () => _finish(-1000, 0, width),
                ),
              ),
          ],
        );
      },
    );
  }

  void _finish(double velX, double velY, double width) {
    _maybe = false;
    if (!_dragging) return;
    final x = width * (1 - controller!.value);
    // Classic branch: cancel if x < width/3 AND (velX < 3500 || |velX| < |velY|).
    final cancel = x < width / 3 && (velX < 3500 || velX.abs() < velY.abs());
    if (!cancel) {
      final remaining = (width - x).clamp(0, width);
      controller!.reverseDuration = Duration(
        milliseconds: math.max(380, (200 * remaining / width).round()),
      );
      navigator!.pop();
      animation!.addStatusListener(_gestureEnded);
      return;
    }
    controller!
        .animateTo(
          1,
          duration: Duration(
            milliseconds: math.max(320, (320 * x / width).round()),
          ),
          curve: tgEaseOutQuint,
        )
        .whenComplete(() {
          if (_dragging) {
            _dragging = false;
            navigator?.didStopUserGesture();
          }
        });
  }

  void _gestureEnded(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _dragging = false;
      navigator?.didStopUserGesture();
      animation!.removeStatusListener(_gestureEnded);
    }
  }
}

Future<T?> showTgDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: '关闭对话框',
  barrierColor: Colors.black.withValues(alpha: .38),
  transitionDuration: const Duration(milliseconds: 190),
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final p = MediaQuery.disableAnimationsOf(context) ? 1.0 : animation.value;
    return Opacity(
      opacity: p.clamp(0, 1),
      child: Transform.scale(
        scale: .94 + .06 * const TgOvershoot(1.3).transform(p),
        child: child,
      ),
    );
  },
);

Future<T?> showTgSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  sheetAnimationStyle: const AnimationStyle(
    duration: TgDuration.sheetOpen,
    reverseDuration: TgDuration.sheetClose,
  ),
  builder: builder,
);

class _TgPopupRoute<T> extends RawDialogRoute<T> {
  _TgPopupRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    required super.transitionDuration,
  }) : super(
         barrierDismissible: true,
         barrierLabel: '关闭菜单',
         barrierColor: Colors.black38,
       );
  @override
  Duration get reverseTransitionDuration => TgDuration.popupDismiss;
}

Future<T?> showTgMessageMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showTgPopup(
  context: context,
  builder: builder,
  centered: true,
  blur: true,
  itemCount: 7,
);
Future<T?> showTgPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Offset? anchor,
  int itemCount = 5,
  bool centered = false,
  bool blur = false,
}) => Navigator.of(context, rootNavigator: true).push(
  _TgPopupRoute<T>(
    transitionDuration: Duration(milliseconds: 150 + 16 * itemCount),
    pageBuilder: (context, _, _) => Stack(
      children: [
        if (blur)
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: centered ? Alignment.center : Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(
                top: centered ? 0 : anchor?.dy ?? 66,
                right: 12,
                left: centered ? 12 : 40,
                bottom: 12,
              ),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 4,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height - 140,
                    maxWidth: centered ? 340 : 268,
                  ),
                  child: SingleChildScrollView(child: builder(context)),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) {
      final p = MediaQuery.disableAnimationsOf(context)
          ? 1.0
          : tgDefaultCurve.transform(animation.value);
      return Opacity(
        opacity: p,
        child: Transform.scale(
          alignment: centered ? Alignment.center : Alignment.topRight,
          scale: .88 + .12 * p,
          child: child,
        ),
      );
    },
  ),
);

class TgBackdropTransitions extends PageTransitionsBuilder {
  const TgBackdropTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child,
      builder: (context, child) {
        final dragging = Navigator.of(context).userGestureInProgress;
        final p = dragging
            ? secondaryAnimation.value
            : const AndroidDecelerate(1).transform(secondaryAnimation.value);
        // ActionBarLayout: scrim alpha = 120 * clamp(widthOffset/width, 0, .8).
        // Background stays put (live previous route); only a dimmer overlays it.
        final cover = p < .8 ? p : .8;
        final scrim = (120 / 255) * cover;
        return Stack(
          children: [
            child!,
            if (p > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: scrim),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
