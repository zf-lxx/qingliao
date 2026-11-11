import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cells/bubble_path.dart';
import '../motion/tg_motion.dart';

/// Original procedural wallpaper, no external bitmap or Telegram artwork.
class TgWallpaper extends CustomPainter {
  final bool dark;
  const TgWallpaper({required this.dark});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(
      dark ? const Color(0xff101d25) : const Color(0xffdce9e5),
      BlendMode.src,
    );
    final p = Paint()
      ..color = (dark ? const Color(0xff86a8a3) : const Color(0xff5d857b))
          .withValues(alpha: dark ? .075 : .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var row = 0; row < size.height / 96 + 1; row++) {
      for (var col = 0; col < size.width / 88 + 1; col++) {
        final x = col * 88.0 + (row.isOdd ? 33 : 0), y = row * 96.0;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((row + col) * .47);
        switch ((row * 3 + col) % 4) {
          case 0:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                const Rect.fromLTWH(-12, -8, 24, 16),
                const Radius.circular(7),
              ),
              p,
            );
            canvas.drawLine(const Offset(-6, 8), const Offset(-11, 14), p);
          case 1:
            canvas.drawArc(
              const Rect.fromLTWH(-12, -12, 24, 24),
              .2,
              math.pi * 1.6,
              false,
              p,
            );
            canvas.drawCircle(const Offset(0, 0), 2, p);
          case 2:
            canvas.drawPath(
              Path()
                ..moveTo(-12, 5)
                ..lineTo(-3, -10)
                ..lineTo(12, 5)
                ..close(),
              p,
            );
            canvas.drawLine(const Offset(-7, 10), const Offset(7, 10), p);
          case 3:
            canvas.drawOval(const Rect.fromLTWH(-11, -6, 22, 12), p);
            canvas.drawLine(const Offset(0, -13), const Offset(0, 13), p);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(TgWallpaper old) => dark != old.dark;
}

class TgBubbleShape extends ShapeBorder {
  final bool mine, grouped, media;
  const TgBubbleShape({
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

class TgTypingDots extends StatefulWidget {
  const TgTypingDots({super.key});
  @override
  State<TgTypingDots> createState() => _TgTypingDotsState();
}

class _TgTypingDotsState extends State<TgTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 15,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _Dots(
          _controller.value,
          Theme.of(context).colorScheme.primary,
          MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}

class _Dots extends CustomPainter {
  final double phase;
  final Color color;
  final bool reduce;
  const _Dots(this.phase, this.color, this.reduce);
  @override
  void paint(Canvas c, Size s) {
    for (var i = 0; i < 3; i++) {
      final t = (phase * 1100 - i * 150).clamp(0.0, 800.0);
      final grow = reduce
          ? 0.0
          : t < 320
          ? Curves.decelerate.transform(t / 320)
          : t < 640
          ? 1 - Curves.decelerate.transform((t - 320) / 320)
          : 0.0;
      c.drawCircle(
        Offset(4 + i * 7, s.height / 2),
        1.33 + grow,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_Dots old) =>
      phase != old.phase || color != old.color || reduce != old.reduce;
}

class TgComposerAction extends StatelessWidget {
  final bool sending, hasText, enabled;
  final VoidCallback onSend, onCamera;
  const TgComposerAction({
    super.key,
    required this.sending,
    required this.hasText,
    required this.enabled,
    required this.onSend,
    required this.onCamera,
  });
  @override
  Widget build(BuildContext context) => PressableScale(
    tooltip: hasText ? '发送' : '发送图片',
    onTap: enabled ? (hasText ? onSend : onCamera) : null,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary
            .withValues(alpha: enabled ? 1 : .4),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: tgEaseOutQuint,
          switchOutCurve: tgEaseOutQuint,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              scale: Tween<double>(begin: .5, end: 1).animate(a),
              child: RotationTransition(
                turns: Tween<double>(begin: -.12, end: 0).animate(a),
                child: child,
              ),
            ),
          ),
          child: sending
              ? const SizedBox(
                  key: ValueKey('busy'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  hasText ? Icons.send_rounded : Icons.camera_alt_rounded,
                  key: ValueKey(hasText),
                  color: Colors.white,
                  size: 23,
                ),
        ),
      ),
    ),
  );
}

class TgSelectableMessage extends StatelessWidget {
  final bool selecting, selected, outgoing;
  final VoidCallback onToggle;
  final Widget child;
  const TgSelectableMessage({
    super.key,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.child,
    this.outgoing = false,
  });
  @override
  Widget build(BuildContext context) {
    // ChatMessageCell: 200ms, EASE_OUT in / EASE_IN out, 35dp. Incoming
    // rows translate; outgoing stays put. Checkbox at left dp(8-35)+dx.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: selecting ? onToggle : null,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 200),
        curve: selecting ? tgEaseOut : tgEaseIn,
        tween: Tween(begin: 0, end: selecting ? 1 : 0),
        builder: (context, t, _) {
          final dx = outgoing ? 0.0 : 35 * t;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Transform.translate(
                  offset: Offset(dx, 0),
                  child: IgnorePointer(ignoring: selecting, child: child),
                ),
              ),
              Positioned(
                left: 8 - 35 + dx,
                bottom: 8,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: .6 + .4 * t,
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? const Color(0xff50ad82)
                            : Colors.transparent,
                        border: Border.all(
                          width: 1.5,
                          color: selected
                              ? const Color(0xff50ad82)
                              : Colors.white38,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class TgSideButtons extends StatelessWidget {
  final bool visible;
  final Widget child;
  const TgSideButtons({super.key, required this.visible, required this.child});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.decelerate,
      offset: visible ? Offset.zero : const Offset(0, 1.6),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 280),
        scale: visible ? 1 : .7,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    ),
  );
}
