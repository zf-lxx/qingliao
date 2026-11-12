import 'package:flutter/widgets.dart';

import '../components/full_page_back_swipe.dart';
import '../render/ql_curves.dart';
import '../theme/app_motion.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Freezes the tab shell (the conversation list) into a texture while a
/// conversation route is covering it, so enter/exit transitions do not
/// re-paint that tree every frame.
final SnapshotController chatShellSnapshotController = SnapshotController();

class ChatShellCover {
  ChatShellCover._();

  static int _covers = 0;

  static void acquire() {
    _covers += 1;
    chatShellSnapshotController.allowSnapshotting = true;
  }

  static void release() {
    if (_covers == 0) return;
    _covers -= 1;
    if (_covers == 0) {
      // Wait one frame so the live list can drop selection and apply the
      // unread/preview mutation before the frozen texture is released.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_covers == 0) {
          chatShellSnapshotController.allowSnapshotting = false;
        }
      });
    }
  }

  @visibleForTesting
  static int get debugCoverCount => _covers;

  @visibleForTesting
  static void debugReset() {
    _covers = 0;
    chatShellSnapshotController.allowSnapshotting = false;
  }
}

/// The shared route for app-level conversation surfaces.
///
/// Its controller is also the single source of truth for a full-page back
/// swipe, so the navigator can paint the real previous route as soon as the
/// current page starts moving. While the conversation is settled it reports
/// itself opaque so the list underneath is not painted every frame; during
/// the enter/exit motion and an in-progress swipe it becomes translucent
/// again without remounting that list.
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

  NavigatorState? _gestureNavigator;
  AnimationController? _gestureController;
  AnimationStatusListener? _gestureStatusListener;
  bool _fullPageBackSwipeActive = false;
  bool _settledCover = false;
  bool _coverAcquired = false;
  Animation<double>? _routeAnimation;
  CurvedAnimation? _curvedAnimation;

  @override
  bool get opaque => _settledCover;

  @override
  Duration get transitionDuration => QlDuration.page;

  @override
  Duration get reverseTransitionDuration => QlDuration.page;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  bool get _fingerDriven => _fullPageBackSwipeActive || popGestureInProgress;

  void _acquireCover() {
    if (_coverAcquired) return;
    _coverAcquired = true;
    ChatShellCover.acquire();
  }

  void _releaseCover() {
    if (!_coverAcquired) return;
    _coverAcquired = false;
    ChatShellCover.release();
  }

  void _attachRouteAnimation() {
    final current = animation;
    if (identical(_routeAnimation, current)) return;
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    _curvedAnimation?.dispose();
    _curvedAnimation = null;
    _routeAnimation = current;
    if (current != null) {
      _curvedAnimation = CurvedAnimation(
        parent: current,
        curve: qlDefaultCurve,
        reverseCurve: const AndroidDecelerate(1),
      );
      current.addStatusListener(_onAnimationStatus);
    }
    _syncSettledCover();
  }

  void _onAnimationStatus(AnimationStatus status) {
    _syncSettledCover();
  }

  void _syncSettledCover() {
    final settled =
        !_fingerDriven && (controller?.status == AnimationStatus.completed);
    if (settled == _settledCover) return;
    _settledCover = settled;
    if (isActive) {
      changedInternalState();
    }
  }

  @override
  TickerFuture didPush() {
    final result = super.didPush();
    _acquireCover();
    _attachRouteAnimation();
    return result;
  }

  @override
  void didReplace(Route<dynamic>? oldRoute) {
    super.didReplace(oldRoute);
    _acquireCover();
    _attachRouteAnimation();
  }

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
    _syncSettledCover();
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
    _syncSettledCover();
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
      child: RepaintBoundary(child: builder(context)),
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
    if (AppMotion.isReduced(context) && !_fingerDriven) {
      return child;
    }
    final effective = _fingerDriven
        ? animation
        : (_curvedAnimation ?? animation);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: FadeTransition(
            opacity: _ScrimOpacity(effective),
            child: const ColoredBox(color: Color(0x60000000)),
          ),
        ),
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(effective),
          transformHitTests: false,
          child: child,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    _routeAnimation = null;
    _curvedAnimation?.dispose();
    _curvedAnimation = null;
    _finishFullPageBackSwipe();
    _releaseCover();
    super.dispose();
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// Maps a 0–1 cover fraction onto 0–1 opacity for a 96/255 black scrim,
/// matching [qlBackScrimOpacity] (clamp the cover at 0.8).
class _ScrimOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  _ScrimOpacity(this.parent);
  @override
  final Animation<double> parent;

  static const _max = 96 / 255;

  @override
  double get value {
    final scrim = qlBackScrimOpacity(parent.value);
    if (scrim <= 0) return 0;
    return (scrim / _max).clamp(0.0, 1.0);
  }
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
