import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Paints immediate, touch-positioned feedback without taking part in the
/// gesture arena, so the wrapped control keeps its tap, long-press, and swipe
/// behavior.
class AppPressRipple extends StatefulWidget {
  const AppPressRipple({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = BorderRadius.zero,
    this.cancelDistance = 12,
  }) : assert(cancelDistance >= 0);

  static const rippleLayerKey = ValueKey<String>('app-press-ripple-layer');

  static final Set<_AppPressRippleState> _active = <_AppPressRippleState>{};

  /// Drops every in-flight ripple immediately so a mid-expansion circle is
  /// not frozen into a list snapshot or still painted when the list returns.
  static void dismissAll() {
    final states = _active.toList(growable: false);
    for (final state in states) {
      state._dismissImmediately();
    }
  }

  final Widget child;
  final Color? color;
  final BorderRadiusGeometry borderRadius;
  final double cancelDistance;

  @override
  State<AppPressRipple> createState() => _AppPressRippleState();
}

class _AppPressRippleState extends State<AppPressRipple>
    with TickerProviderStateMixin {
  late final AnimationController _expansionController;
  late final AnimationController _opacityController;
  late final Listenable _animation;

  int? _pointer;
  Offset? _origin;
  Offset? _downPosition;
  bool _cancelled = false;
  int _generation = 0;
  ModalRoute<dynamic>? _route;
  Animation<double>? _secondaryAnimation;

  @override
  void initState() {
    super.initState();
    _expansionController = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
    );
    _opacityController = AnimationController(
      vsync: this,
      duration: AppMotion.quick,
    );
    _animation = Listenable.merge([_expansionController, _opacityController]);
    AppPressRipple._active.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expansionController.duration = AppMotion.duration(
      context,
      AppMotion.deliberate,
    );
    _opacityController.duration = AppMotion.duration(context, AppMotion.quick);
    // Tapping a row pushes the chat before this listener can see pointer-up.
    // The circle then stays at whatever radius it had reached, and because the
    // chat route is opaque the stain only becomes visible on the way back.
    // ModalRoute.isCurrent on a nested tab navigator also stays true when the
    // chat is pushed on the root navigator, so this is only a fallback —
    // ChatShellCover.dismisses every ripple before snapshotting the list.
    _bindRoute(ModalRoute.of(context));
    _dismissIfCovered();
  }

  void _bindRoute(ModalRoute<dynamic>? route) {
    if (identical(_route, route)) return;
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimation);
    _secondaryAnimation = null;
    _route = route;
    final secondary = route?.secondaryAnimation;
    if (secondary != null) {
      _secondaryAnimation = secondary;
      secondary.addStatusListener(_onSecondaryAnimation);
    }
  }

  void _onSecondaryAnimation(AnimationStatus status) {
    // Another route on the same navigator is arriving or leaving — drop any
    // mid-expansion circle so it cannot freeze or reappear.
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed ||
        status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _dismissImmediately();
    }
  }

  void _dismissIfCovered() {
    final route = _route ?? (mounted ? ModalRoute.of(context) : null);
    if (route != null && !route.isCurrent) {
      _dismissImmediately();
    }
  }

  void _dismissImmediately() {
    final hadRipple = _origin != null || _pointer != null;
    _pointer = null;
    _downPosition = null;
    _cancelled = true;
    _generation++;
    if (_opacityController.value != 0) {
      _opacityController.value = 0;
    }
    _expansionController.stop();
    _origin = null;
    if (!hadRipple || !mounted) return;
    // didChangeDependencies may run during build; the coming build already
    // sees _origin == null. Gesture / route callbacks are between frames and
    // must mark dirty so a snapshot taken this frame is already clean.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    AppPressRipple._active.remove(this);
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimation);
    _secondaryAnimation = null;
    _route = null;
    _expansionController.dispose();
    _opacityController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _cancelled = false;
    _generation++;
    setState(() => _origin = event.localPosition);

    _opacityController.stop();
    _opacityController.value = 1;
    if (AppMotion.isReduced(context)) {
      _expansionController.value = 1;
    } else {
      _expansionController.forward(from: 0);
    }
    // onTap may push a new route in this frame, before pointer-up. Recheck
    // after the frame so a same-navigator cover is not missed if
    // didChangeDependencies already ran while _origin was still null.
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _dismissIfCovered();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled) return;
    final downPosition = _downPosition;
    if (downPosition == null ||
        (event.localPosition - downPosition).distance <=
            widget.cancelDistance) {
      return;
    }
    _cancelled = true;
    _hideRipple();
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downPosition = null;
    if (!_cancelled) _hideRipple();
  }

  void _hideRipple() {
    if (!mounted) return;
    final generation = _generation;
    if (AppMotion.isReduced(context)) {
      _opacityController.value = 0;
      if (mounted && generation == _generation) {
        setState(() => _origin = null);
      }
      return;
    }
    _opacityController.reverse().whenCompleteOrCancel(() {
      if (!mounted || generation != _generation) return;
      setState(() => _origin = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final origin = _origin;
    // A square-cornered wrapper with no ripple has nothing to clip, but the
    // rasteriser still pushes a rounded-rect clip layer per instance — and the
    // chat list wraps every row in one. Clip.none skips the layer while keeping
    // the wrapper in the tree, so the child's element identity survives a press.
    final hasNothingToClip =
        origin == null && widget.borderRadius == BorderRadius.zero;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        clipBehavior: hasNothingToClip ? Clip.none : Clip.hardEdge,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (origin != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => CustomPaint(
                      key: AppPressRipple.rippleLayerKey,
                      painter: _AppPressRipplePainter(
                        origin: origin,
                        color: widget.color ?? context.colors.textPrimary,
                        progress: AppMotion.standard.transform(
                          _expansionController.value,
                        ),
                        opacity: _opacityController.value,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppPressRipplePainter extends CustomPainter {
  const _AppPressRipplePainter({
    required this.origin,
    required this.color,
    required this.progress,
    required this.opacity,
  });

  final Offset origin;
  final Color color;
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.025 * opacity),
    );

    final farthestX = math.max(origin.dx, size.width - origin.dx);
    final farthestY = math.max(origin.dy, size.height - origin.dy);
    final radius = math.sqrt(farthestX * farthestX + farthestY * farthestY);
    canvas.drawCircle(
      origin,
      radius * progress,
      Paint()..color = color.withValues(alpha: 0.10 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _AppPressRipplePainter oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.opacity != opacity;
}
