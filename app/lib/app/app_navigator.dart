import 'package:flutter/widgets.dart';

import '../components/full_page_back_swipe.dart';
import '../render/ql_curves.dart';
import '../theme/app_motion.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// The shared route for app-level conversation surfaces.
///
/// Its controller is also the single source of truth for a full-page back
/// swipe, so the navigator can paint the real previous route as soon as the
/// current page starts moving.
class AppChatPageRoute<T> extends PageRoute<T>
    implements FullPageBackSwipeDriver {
  AppChatPageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.maintainState = true,
  }) : super(allowSnapshotting: false);

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  bool get opaque => false;

  NavigatorState? _gestureNavigator;
  AnimationController? _gestureController;
  AnimationStatusListener? _gestureStatusListener;
  bool _fullPageBackSwipeActive = false;

  @override
  Duration get transitionDuration => QlDuration.page;

  @override
  Duration get reverseTransitionDuration => QlDuration.page;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get canStartFullPageBackSwipe =>
      !_fullPageBackSwipeActive &&
      popGestureEnabled &&
      (controller?.isCompleted ?? false);

  @override
  bool startFullPageBackSwipe() {
    final animationController = controller;
    final routeNavigator = navigator;
    if (!canStartFullPageBackSwipe ||
        animationController == null ||
        routeNavigator == null) {
      return false;
    }
    animationController.stop();
    _fullPageBackSwipeActive = true;
    _gestureNavigator = routeNavigator;
    _gestureController = animationController;
    routeNavigator.didStartUserGesture();
    return true;
  }

  @override
  void updateFullPageBackSwipe(double progress) {
    if (!_fullPageBackSwipeActive || !isCurrent) return;
    controller?.value = 1 - progress.clamp(0.0, 1.0);
  }

  @override
  void cancelFullPageBackSwipe() {
    final animationController = _gestureController;
    if (!_fullPageBackSwipeActive || animationController == null) return;
    final restoreRoute = isCurrent || isActive;
    final target = restoreRoute ? 1.0 : 0.0;
    final progress = animationController.value;
    if (restoreRoute) {
      animationController.animateTo(
        target,
        duration: qlBackCancelDuration(1 - progress, 1),
        curve: const AndroidDecelerate(1),
      );
    } else {
      animationController.animateBack(
        target,
        duration: qlBackFinishDuration(progress, 1),
        curve: const AndroidDecelerate(1),
      );
    }
    _finishGestureWhenSettled(animationController);
  }

  @override
  void commitFullPageBackSwipe(VoidCallback? beforePop) {
    final animationController = _gestureController;
    final routeNavigator = _gestureNavigator;
    if (!_fullPageBackSwipeActive ||
        animationController == null ||
        routeNavigator == null) {
      return;
    }
    if (!isCurrent ||
        willHandlePopInternally ||
        popDisposition != RoutePopDisposition.pop) {
      cancelFullPageBackSwipe();
      return;
    }
    final remaining = animationController.value;
    try {
      beforePop?.call();
      routeNavigator.pop<T>();
    } catch (_) {
      cancelFullPageBackSwipe();
      rethrow;
    }
    if (animationController.isAnimating) {
      animationController.animateBack(
        0,
        duration: qlBackFinishDuration(remaining, 1),
        curve: const AndroidDecelerate(1),
      );
    }
    _finishGestureWhenSettled(animationController);
  }

  void _finishGestureWhenSettled(AnimationController animationController) {
    final existingListener = _gestureStatusListener;
    if (existingListener != null) {
      animationController.removeStatusListener(existingListener);
    }
    if (!animationController.isAnimating) {
      _finishFullPageBackSwipe();
      return;
    }
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      animationController.removeStatusListener(listener);
      if (identical(_gestureStatusListener, listener)) {
        _gestureStatusListener = null;
      }
      _finishFullPageBackSwipe();
    };
    _gestureStatusListener = listener;
    animationController.addStatusListener(listener);
  }

  void _finishFullPageBackSwipe() {
    if (!_fullPageBackSwipeActive) return;
    final listener = _gestureStatusListener;
    final animationController = _gestureController;
    if (listener != null && animationController != null) {
      animationController.removeStatusListener(listener);
    }
    _gestureStatusListener = null;
    _gestureController = null;
    _fullPageBackSwipeActive = false;
    final routeNavigator = _gestureNavigator;
    _gestureNavigator = null;
    if (routeNavigator?.mounted ?? false) {
      routeNavigator!.didStopUserGesture();
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.usesInPlaceDesktopNavigation(context)) {
      return AppMotion.desktopRouteSurface(context, child);
    }
    if (AppMotion.isReduced(context) && !_fullPageBackSwipeActive) {
      return child;
    }
    final finger = _fullPageBackSwipeActive || popGestureInProgress;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final raw = animation.value;
        final t = finger
            ? raw
            : (animation.status == AnimationStatus.reverse ||
                  animation.status == AnimationStatus.dismissed)
            ? const AndroidDecelerate(1).transform(raw)
            : qlDefaultCurve.transform(raw);
        final width = MediaQuery.sizeOf(context).width;
        final translationX = (1 - t) * width;
        final scrim = qlBackScrimOpacity(t);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (scrim > 0)
              IgnorePointer(
                child: ColoredBox(color: Color.fromRGBO(0, 0, 0, scrim)),
              ),
            Transform.translate(
              offset: Offset(translationX, 0),
              transformHitTests: false,
              child: Transform.scale(
                alignment: Alignment.centerLeft,
                scale: qlBackPageScale(translationX),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _finishFullPageBackSwipe();
    super.dispose();
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

Future<T?> pushAppChatRoute<T>(BuildContext context, Route<T> route) {
  final navigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  return navigator.push(route);
}

/// Replaces the current conversation route. If the caller is still on a
/// tab-local utility page (for example the create-group form), close that page
/// before opening the conversation in the app-level chat navigator.
Future<T?> replaceWithAppChatRoute<T, TO>(
  BuildContext context,
  Route<T> route, {
  TO? result,
}) {
  final sourceNavigator = Navigator.of(context);
  final rootNavigator =
      appNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  if (identical(sourceNavigator, rootNavigator)) {
    // A pane can share the root navigator without owning its route. Keep the
    // shell underneath the conversation, including roots with local history.
    if (ModalRoute.of(context)?.isFirst != false) {
      return rootNavigator.push<T>(route);
    }
    return sourceNavigator.pushReplacement<T, TO>(route, result: result);
  }
  if (sourceNavigator.canPop()) sourceNavigator.pop<TO>(result);
  return rootNavigator.push<T>(route);
}
