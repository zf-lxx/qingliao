//
//  message_swipe_reply.dart
//
//  The leftward drag that turns a transcript row into the composer's reply
//  target. The whole row follows the finger — the empty space beside a short
//  bubble and the avatar included — a reply glyph fades in behind its trailing
//  edge, one tick is felt when the release would commit, and letting go either
//  springs the row home or hands the message to the composer.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../platform/adaptive_platform.dart';
import '../render/ql_curves.dart';
import '../theme/app_theme.dart';

/// Start distance in centimetres, converted at 160 logical pixels per inch.
const double messageSwipeReplyStartCm = 1.2;

/// Start distance in logical pixels (~75.6). Independent of devicePixelRatio.
double messageSwipeReplyStartDistance({double devicePixelRatio = 1}) =>
    (messageSwipeReplyStartCm / 2.54) * 160;

/// Horizontal must be at least this many times the vertical movement.
const double messageSwipeReplyMinDominance = 2;

/// Travel at which letting go commits the reply, in logical pixels.
const double messageSwipeReplyTrigger = 96;

/// Travel that follows the finger 1:1 before resistance starts.
const double messageSwipeReplyRestingLimit = 120;

/// Travel the row never passes, however hard the finger pulls.
const double messageSwipeReplyHardLimit = 120;

/// Travel over which the trailing glyph fades from invisible to opaque.
const double messageSwipeReplyGlyphFade = 96;

/// Inset of the glyph from the row's trailing edge.
const double messageSwipeReplyGlyphInset = 16;

/// Glyph size, matching the reply glyph the action menu uses.
const double messageSwipeReplyGlyphSize = 18;

/// Fraction of the over-pull that survives past the resting limit.
const double messageSwipeReplyResistance = 0.34;

/// Damps a requested travel (negative is leftward) into the offset the row
/// actually takes: 1:1 up to [messageSwipeReplyRestingLimit], then
/// [messageSwipeReplyResistance] of every further pixel, capped at
/// [messageSwipeReplyHardLimit].
///
/// Callers feed either the accumulated offset plus the new delta (a drag
/// stream, which damps progressively) or the raw travel from the touch origin
/// (a pointer path that knows the whole gesture). Both read the same.
double messageSwipeReplyStartPx(BuildContext context) =>
    messageSwipeReplyStartDistance();

/// True when a leftward drag has gone far enough, with horizontal clearly
/// greater than vertical, to start following as a reply swipe.
bool messageSwipeReplyAcceptsDirection({
  required double dx,
  required double dy,
  double? startPx,
  double dominance = messageSwipeReplyMinDominance,
}) {
  final start = startPx ?? messageSwipeReplyStartDistance();
  return dx <= -start && dx.abs() >= dy.abs() * dominance;
}

/// True when the pointer has moved far enough to be a scroll (or a rightward
/// drag) rather than a reply swipe.
bool messageSwipeReplyRejectsAsScroll({
  required double dx,
  required double dy,
  double? startPx,
  double dominance = messageSwipeReplyMinDominance,
}) {
  final start = startPx ?? messageSwipeReplyStartDistance();
  final distance = Offset(dx, dy).distance;
  if (distance < start) return false;
  if (dx >= 0) return true;
  return dy.abs() * dominance > dx.abs();
}

double messageSwipeReplyOffset(double travel) {
  if (travel >= -messageSwipeReplyRestingLimit) {
    return travel.clamp(-messageSwipeReplyHardLimit, 0).toDouble();
  }
  final extra = -travel - messageSwipeReplyRestingLimit;
  final damped =
      messageSwipeReplyRestingLimit + extra * messageSwipeReplyResistance;
  return -damped.clamp(0, messageSwipeReplyHardLimit).toDouble();
}

/// Whether a released drag commits. Only crossing the trigger counts; a flick
/// that never reached it springs home without opening a reply.
bool messageSwipeReplyCommits({
  required double offset,
  double? primaryVelocity,
}) => offset <= -messageSwipeReplyTrigger;

/// One row's swipe travel.
///
/// [buildMessageSwipeReply] animates from [travel]. A host that reads raw
/// pointers instead of the gesture arena — the desktop touch path in
/// `MessageBubble` — drives the same travel through [dragTo], [finish] and
/// [cancel], so both paths share the thresholds, the damping and the tick.
class MessageSwipeReplyController {
  MessageSwipeReplyController({required TickerProvider vsync})
    : _travel = AnimationController.unbounded(vsync: vsync);

  final AnimationController _travel;
  bool _tickArmed = true;
  bool _disposed = false;
  int _tickCount = 0;

  /// Set by the host's build so a reduced-motion setting shortens the spring
  /// home the way it shortens every other surface.
  Duration settleDuration = QlDuration.swipeSnap;

  double _gateX = 0;
  double _gateY = 0;
  double _startPx = 0;
  bool _gated = true;
  bool _rejected = false;

  /// The row listens to this.
  Listenable get travel => _travel;

  /// Current offset in logical pixels; negative while dragged left.
  double get offset => _travel.value;

  /// Threshold ticks felt since the controller was created.
  @visibleForTesting
  int get tickCount => _tickCount;

  /// Claims a fresh drag: stops a running spring and re-arms the tick.
  void beginDrag({double startPx = 0}) {
    if (_disposed) return;
    _travel.stop();
    _tickArmed = _travel.value > -messageSwipeReplyTrigger;
    _startPx = startPx;
    _gateX = 0;
    _gateY = 0;
    _gated = startPx <= 0;
    _rejected = false;
  }

  /// Moves by one drag delta.
  void dragBy(double delta, {double dy = 0}) {
    if (_disposed || _rejected) return;
    if (!_gated) {
      _gateX += delta;
      _gateY += dy;
      if (messageSwipeReplyAcceptsDirection(
        dx: _gateX,
        dy: _gateY,
        startPx: _startPx,
      )) {
        _gated = true;
      } else if (messageSwipeReplyRejectsAsScroll(
        dx: _gateX,
        dy: _gateY,
        startPx: _startPx,
      )) {
        _rejected = true;
      }
      return;
    }
    _apply(_travel.value + delta);
  }

  /// Moves to an absolute travel from the gesture origin.
  void dragTo(double travel, {double dy = 0, double startPx = 0}) {
    if (_disposed || _rejected) return;
    final threshold = startPx > 0 ? startPx : _startPx;
    if (!_gated && threshold > 0) {
      if (messageSwipeReplyAcceptsDirection(
        dx: travel,
        dy: dy,
        startPx: threshold,
      )) {
        _gated = true;
      } else if (messageSwipeReplyRejectsAsScroll(
        dx: travel,
        dy: dy,
        startPx: threshold,
      )) {
        _rejected = true;
        return;
      } else {
        return;
      }
    }
    _apply(travel);
  }

  void _apply(double requested) {
    if (_disposed) return;
    final next = messageSwipeReplyOffset(requested);
    if (next == _travel.value) return;
    _travel.value = next;
    if (next <= -messageSwipeReplyTrigger) {
      if (_tickArmed) {
        _tickArmed = false;
        _tickCount++;
        unawaited(HapticFeedback.selectionClick());
      }
    } else {
      // Dragging back out re-arms it, so a second attempt ticks again.
      _tickArmed = true;
    }
  }

  /// Lets go: fires [onReply] when the travel or the flick committed, then
  /// springs the row home either way.
  void finish({required VoidCallback? onReply, double? primaryVelocity}) {
    if (_disposed) return;
    if (messageSwipeReplyCommits(
      offset: _travel.value,
      primaryVelocity: primaryVelocity,
    )) {
      onReply?.call();
    }
    cancel();
  }

  /// Springs the row home without replying.
  void cancel() {
    _tickArmed = true;
    // A scheduled put-back can outlive the row that scheduled it.
    if (_disposed) return;
    if (_travel.value == 0 && !_travel.isAnimating) return;
    _travel.animateTo(
      0,
      duration: settleDuration,
      curve: const AndroidDecelerate(1),
    );
  }

  void dispose() {
    _disposed = true;
    _travel.dispose();
  }
}

/// Wraps [child] in the swipe affordance: a row-wide recognizer, the trailing
/// glyph, and the travel transform.
///
/// A function rather than a widget on the transcript's hot path — every mounted
/// message pays for this, and a wrapper State would be one more element per
/// bubble. A host with nowhere to keep a controller uses
/// [MessageSwipeReplyRow] instead.
///
/// The recognizer covers the row rather than the bubble: a two-word bubble is
/// ~55px wide, and a swipe that has to land on it exactly reads as a gesture
/// that does not work. Desktop stays out — a mouse drag there selects text —
/// and a host that reads raw pointers keeps charge by driving [controller].
Widget buildMessageSwipeReply({
  required BuildContext context,
  required MessageSwipeReplyController controller,
  required Widget child,
  VoidCallback? onReply,
  bool swipeEnabled = true,
}) {
  controller.settleDuration = MediaQuery.disableAnimationsOf(context)
      ? const Duration(milliseconds: 1)
      : QlDuration.swipeSnap;
  final interactive =
      onReply != null &&
      swipeEnabled &&
      !isDesktopTargetPlatform(Theme.of(context).platform);
  if ((onReply == null || !swipeEnabled) && controller.offset != 0) {
    // Multi-select or an armed text selection took the row over mid-drag and
    // left it displaced with no recognizer to finish the job. Desktop hosts
    // still own raw touch drags even though this wrapper excludes mouse drags.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.cancel());
  }
  final row = interactive
      ? RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            MessageSwipeReplyGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  MessageSwipeReplyGestureRecognizer
                >(
                  () => MessageSwipeReplyGestureRecognizer(
                    startPx: messageSwipeReplyStartPx(context),
                  ),
                  (instance) {
                    instance.onStart = (_) => controller.beginDrag();
                    instance.onUpdate = (details) => controller.dragBy(
                      details.delta.dx,
                      dy: details.delta.dy,
                    );
                    instance.onEnd = (details) => controller.finish(
                      onReply: onReply,
                      primaryVelocity: details.primaryVelocity,
                    );
                    instance.onCancel = controller.cancel;
                  },
                ),
          },
          child: child,
        )
      : child;
  // The offset only moves this Stack, so it drives an AnimatedBuilder instead
  // of a setState: every drag update and every frame of the spring would
  // otherwise rebuild the whole row — spans, recognizers, colour chains.
  return AnimatedBuilder(
    animation: controller.travel,
    child: row,
    builder: (context, row) {
      final offset = controller.offset;
      return Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          // Every mounted row would pay for this glyph — an Icon is a glyph
          // layout, and at rest opacity 0 hides it. Swap in a const placeholder
          // until a swipe starts; the child count stays the same so the sibling
          // below keeps its element.
          if (offset == 0)
            const SizedBox.shrink()
          else
            Padding(
              padding: const EdgeInsets.only(
                right: messageSwipeReplyGlyphInset,
              ),
              child: Opacity(
                opacity: (math.min(
                  1,
                  math.max(0, -offset) / messageSwipeReplyGlyphFade,
                )).toDouble(),
                child: AppIcon(
                  HeroAppIcons.reply,
                  size: messageSwipeReplyGlyphSize,
                  color: AppTheme.brand,
                ),
              ),
            ),
          Transform.translate(offset: Offset(offset, 0), child: row),
        ],
      );
    },
  );
}

/// [buildMessageSwipeReply] with a controller of its own, for a host that has
/// nowhere to keep one — an album row is built by a stateless widget.
class MessageSwipeReplyRow extends StatefulWidget {
  const MessageSwipeReplyRow({
    super.key,
    required this.child,
    this.onReply,
    this.controller,
    this.swipeEnabled = true,
  });

  final Widget child;

  /// Fires when a released drag committed. Null leaves the row inert — no
  /// recognizer, no glyph — which is what previews and read-only surfaces pass.
  final VoidCallback? onReply;

  /// Parent-owned travel; the row creates and disposes its own when null.
  final MessageSwipeReplyController? controller;

  /// False while another gesture owns the row, e.g. an armed mobile text
  /// selection or multi-select.
  final bool swipeEnabled;

  @override
  State<MessageSwipeReplyRow> createState() => _MessageSwipeReplyRowState();
}

class _MessageSwipeReplyRowState extends State<MessageSwipeReplyRow>
    with SingleTickerProviderStateMixin {
  late final MessageSwipeReplyController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    _ownsController = provided == null;
    _controller = provided ?? MessageSwipeReplyController(vsync: this);
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildMessageSwipeReply(
    context: context,
    controller: _controller,
    onReply: widget.onReply,
    swipeEnabled: widget.swipeEnabled,
    child: widget.child,
  );
}

/// Claims a leftward reply swipe only after [startPx] and a clearly horizontal
/// path, so a vertical transcript scroll keeps the arena.
class MessageSwipeReplyGestureRecognizer extends OneSequenceGestureRecognizer {
  MessageSwipeReplyGestureRecognizer({
    required this.startPx,
    this.dominance = messageSwipeReplyMinDominance,
    super.debugOwner,
    super.supportedDevices,
  });

  final double startPx;
  final double dominance;
  GestureDragStartCallback? onStart;
  GestureDragUpdateCallback? onUpdate;
  GestureDragEndCallback? onEnd;
  GestureDragCancelCallback? onCancel;

  Offset _origin = Offset.zero;
  int? _pointer;
  bool _accepted = false;
  VelocityTracker? _velocity;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _origin = event.position;
    _pointer = event.pointer;
    _accepted = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      final travel = event.position - _origin;
      if (!_accepted) {
        if (messageSwipeReplyRejectsAsScroll(
          dx: travel.dx,
          dy: travel.dy,
          startPx: startPx,
          dominance: dominance,
        )) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          _reset();
          return;
        }
        if (messageSwipeReplyAcceptsDirection(
          dx: travel.dx,
          dy: travel.dy,
          startPx: startPx,
          dominance: dominance,
        )) {
          _accepted = true;
          resolve(GestureDisposition.accepted);
          onStart?.call(
            DragStartDetails(globalPosition: _origin, kind: event.kind),
          );
          onUpdate?.call(
            DragUpdateDetails(
              globalPosition: event.position,
              delta: Offset(travel.dx, travel.dy),
              primaryDelta: travel.dx,
            ),
          );
        }
        return;
      }
      onUpdate?.call(
        DragUpdateDetails(
          globalPosition: event.position,
          delta: event.delta,
          primaryDelta: event.delta.dx,
        ),
      );
    } else if (event is PointerUpEvent) {
      stopTrackingPointer(event.pointer);
      if (_accepted) {
        final velocity = _velocity?.getVelocity() ?? Velocity.zero;
        onEnd?.call(
          DragEndDetails(
            velocity: velocity,
            primaryVelocity: velocity.pixelsPerSecond.dx,
          ),
        );
      } else {
        resolve(GestureDisposition.rejected);
      }
      _reset();
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      if (_accepted) {
        onCancel?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      _reset();
    }
  }

  void _reset() {
    _pointer = null;
    _accepted = false;
    _velocity = null;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_accepted) onCancel?.call();
    _reset();
  }

  @override
  String get debugDescription => 'messageSwipeReply';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}
