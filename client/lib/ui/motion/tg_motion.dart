import 'dart:math' as math;

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

/// Independently implemented navigation: full-width foreground, quarter-width
/// background parallax. The latter is a Qingliao choice, not an upstream value.
class TgPageRoute<T> extends PageRoute<T> {
  final Widget page;
  bool _dragging = false;
  TgPageRoute({required this.page, super.settings});
  @override
  Duration get transitionDuration => TgDuration.page;
  @override
  Duration get reverseTransitionDuration => TgDuration.page;
  @override
  bool get opaque => true;
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
            : tgEaseOutQuint.transform(animation.value);
        final secondary = tgEaseOutQuint.transform(secondaryAnimation.value);
        return Transform.translate(
          offset: Offset(width * (1 - primary) - width * .25 * secondary, 0),
          child: Stack(
            children: [
              Positioned.fill(child: child!),
              if (secondary > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .30 * secondary),
                    ),
                  ),
                ),
              if (canPop && isCurrent)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 24,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: (_) {
                      if (!isCurrent ||
                          animation.status != AnimationStatus.completed ||
                          popDisposition == RoutePopDisposition.doNotPop) {
                        return;
                      }
                      _dragging = true;
                      controller!.stop();
                      navigator!.didStartUserGesture();
                    },
                    onHorizontalDragUpdate: (d) {
                      if (_dragging) {
                        controller!.value =
                            (controller!.value - d.delta.dx / width).clamp(
                              0.0,
                              1.0,
                            );
                      }
                    },
                    onHorizontalDragEnd: (d) =>
                        _finish(d.velocity.pixelsPerSecond.dx, width),
                    onHorizontalDragCancel: () => _finish(-1000, width),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _finish(double velocity, double width) {
    if (!_dragging) return;
    final finish =
        velocity > 700 || (velocity > -700 && controller!.value < .65);
    if (finish) {
      controller!.reverseDuration = Duration(
        milliseconds: math.max(50, (200 * controller!.value).round()),
      );
      navigator!.pop();
    } else {
      controller!
          .animateTo(
            1,
            duration: Duration(
              milliseconds: math.max(
                120,
                (320 * (1 - controller!.value)).round(),
              ),
            ),
            curve: tgEaseOutQuint,
          )
          .whenComplete(() {
            if (_dragging) {
              _dragging = false;
              navigator?.didStopUserGesture();
            }
          });
      return;
    }
    controller!.reverseDuration = Duration(
      milliseconds: math.max(50, (200 * controller!.value).round()),
    );
    animation!.addStatusListener(_gestureEnded);
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

Future<T?> showTgPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Offset? anchor,
  int itemCount = 5,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭菜单',
  barrierColor: Colors.black.withValues(alpha: .28),
  transitionDuration: Duration(milliseconds: 150 + 16 * itemCount),
  pageBuilder: (context, _, _) => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(top: anchor?.dy ?? 60, right: 12, left: 40),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(width: 268, child: builder(context)),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, animation, _, child) {
    final t = MediaQuery.disableAnimationsOf(context)
        ? 1.0
        : tgDefaultCurve.transform(animation.value);
    return FadeTransition(
      opacity: animation,
      child: Transform.scale(
        alignment: Alignment.topRight,
        scale: .88 + .12 * t,
        child: child,
      ),
    );
  },
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
        final p = tgEaseOutQuint.transform(secondaryAnimation.value);
        return Transform.translate(
          offset: Offset(-MediaQuery.sizeOf(context).width * .25 * p, 0),
          child: Stack(
            children: [
              child!,
              if (p > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .30 * p),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
