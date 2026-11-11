import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tg_motion.dart';

const _curve = tgAndroidDefaultCurve;

class ImageRectTween extends RectTween {
  ImageRectTween({super.begin, super.end});
  @override
  Rect? lerp(double t) => Rect.lerp(begin, end, _curve.transform(t));
}

Future<void> openImageViewer(
  BuildContext context, {
  required Uint8List bytes,
  required String tag,
  required String sender,
  required String time,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, animation, _) => ImageViewer(
      bytes: bytes,
      tag: tag,
      sender: sender,
      time: time,
      routeAnimation: animation,
    ),
    transitionsBuilder: (_, _, _, child) => child,
  ),
);

class ImageViewer extends StatefulWidget {
  final Uint8List bytes;
  final String tag, sender, time;
  final Animation<double> routeAnimation;
  const ImageViewer({
    super.key,
    required this.bytes,
    required this.tag,
    required this.sender,
    required this.time,
    required this.routeAnimation,
  });
  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  Matrix4Tween? _zoom;
  Offset _doubleTap = Offset.zero;
  double _drag = 0, _snapFrom = 0;
  bool _bars = true, _zoomed = false, _closing = false;
  static const _media = MethodChannel('xyz.qingliao.app/media');
  @override
  void initState() {
    super.initState();
    _motion.addListener(() {
      if (_zoom case final tween?) {
        _transform.value = tween.transform(
          tgPhotoMoveCurve.transform(_motion.value),
        );
      } else {
        setState(
          () => _drag =
              _snapFrom * (1 - tgPhotoMoveCurve.transform(_motion.value)),
        );
      }
    });
  }

  void _toggleZoom() {
    final target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-_doubleTap.dx * 2, -_doubleTap.dy * 2, 0, 1)
            ..scaleByDouble(3, 3, 1, 1));
    setState(() => _zoomed = !_zoomed);
    _zoom = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _motion.forward(from: 0);
  }

  Future<void> _action(String method) async {
    try {
      await _media.invokeMethod(method, {
        'bytes': widget.bytes,
        'name': 'qingliao-${DateTime.now().millisecondsSinceEpoch}.jpg',
      });
      if (mounted && method == 'save') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存到相册')));
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? '操作失败')));
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前平台不支持此操作')));
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.routeAnimation,
    builder: (context, _) {
      final fade = (1 - _drag.abs() / MediaQuery.sizeOf(context).height * 1.5)
          .clamp(0.0, 1.0);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha:
                      tgAndroidDefaultCurve.transform(
                        widget.routeAnimation.value,
                      ) *
                      fade,
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _bars = !_bars),
                onDoubleTapDown: (d) => _doubleTap = d.localPosition,
                onDoubleTap: _toggleZoom,
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 5,
                    panEnabled: _zoomed,
                    onInteractionStart: (_) {
                      _motion.stop();
                    },
                    onInteractionUpdate: (d) {
                      final scale = _transform.value.getMaxScaleOnAxis();
                      final zoomed = scale > 1.03;
                      if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
                      if (!_zoomed && d.pointerCount == 1) {
                        setState(() => _drag += d.focalPointDelta.dy);
                      }
                    },
                    onInteractionEnd: (d) {
                      if (_zoomed || _closing) return;
                      if (_drag.abs() > 100 ||
                          d.velocity.pixelsPerSecond.dy.abs() > 850) {
                        _closing = true;
                        Navigator.of(context).pop();
                      } else {
                        _snapFrom = _drag;
                        _zoom = null;
                        _motion.forward(from: 0);
                      }
                    },
                    child: Center(
                      child: Hero(
                        tag: widget.tag,
                        curve: Curves.linear,
                        createRectTween: (begin, end) =>
                            ImageRectTween(begin: begin, end: end),
                        child: Image.memory(widget.bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_bars)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: widget.routeAnimation,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      color: const Color(0x66000000),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.sender,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  widget.time,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_bars)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: widget.routeAnimation,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      color: const Color(0x66000000),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: '保存到相册',
                            onPressed: () => _action('save'),
                            icon: const Icon(Icons.download_outlined),
                          ),
                          IconButton(
                            tooltip: '分享',
                            onPressed: () => _action('share'),
                            icon: const Icon(Icons.share_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
