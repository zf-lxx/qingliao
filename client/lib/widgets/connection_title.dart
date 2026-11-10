import 'dart:async';

import 'package:flutter/material.dart';

import '../core/chat_engine.dart';
import 'tg_motion.dart';

/// The title changes in place, never moving the search/list below the app bar.
class ConnectionTitle extends StatefulWidget {
  final ChatEngine engine;
  final String title;
  final TextStyle? style;
  const ConnectionTitle({
    super.key,
    required this.engine,
    required this.title,
    this.style,
  });
  @override
  State<ConnectionTitle> createState() => _ConnectionTitleState();
}

class _ConnectionTitleState extends State<ConnectionTitle> {
  Timer? _delay;
  bool _show = false;
  bool get _busy => !widget.engine.online || widget.engine.syncing;
  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ConnectionTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_changed);
      widget.engine.addListener(_changed);
      _delay?.cancel();
      _delay = null;
      _show = false;
      _changed();
    }
  }

  void _changed() {
    if (!_busy) {
      _delay?.cancel();
      _delay = null;
      if (_show && mounted) setState(() => _show = false);
    } else if (!_show && _delay == null) {
      _delay = Timer(const Duration(seconds: 1), () {
        _delay = null;
        if (mounted && _busy) setState(() => _show = true);
      });
    } else if (_show && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    widget.engine.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final busy = _busy && _show;
    final label = widget.engine.syncing ? '更新中' : '连接中';
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 0 : 220),
        switchInCurve: tgAndroidDefaultCurve,
        switchOutCurve: tgAndroidDefaultCurve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                0,
                (1 - animation.value) *
                    (animation.status == AnimationStatus.reverse ? 20 : -20),
              ),
              child: child,
            ),
          ),
        ),
        child: busy
            ? Semantics(
                key: ValueKey(label),
                label: '$label…',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: widget.style?.fontSize == 12 ? 11 : 17,
                      height: widget.style?.fontSize == 12 ? 11 : 17,
                      child: const CircularProgressIndicator(strokeWidth: 1.7),
                    ),
                    const SizedBox(width: 9),
                    Text(label, style: widget.style),
                    _AnimatedDots(style: widget.style, animate: !reduce),
                  ],
                ),
              )
            : Text(
                widget.title,
                key: ValueKey(widget.title),
                style: widget.style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  final TextStyle? style;
  final bool animate;
  const _AnimatedDots({this.style, required this.animate});
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  double _dotOpacity(int index) {
    final ms = _animation.value * 1700;
    final start = index * 150;
    if (ms < start) return 0;
    if (ms < start + 300) return tgDefaultCurve.transform((ms - start) / 300);
    if (ms < 1000) return 1;
    if (ms < 1400) return 1 - tgDefaultCurve.transform((ms - 1000) / 400);
    return 0;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Opacity(
            opacity: widget.animate ? _dotOpacity(i) : 1,
            child: Text('.', style: widget.style),
          ),
      ],
    ),
  );
}
