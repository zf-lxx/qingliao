import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/image_viewer.dart';

/// Fixed 240×160 box so the list never jumps when bytes arrive.
class ChatImage extends StatelessWidget {
  static const boxWidth = 240.0, boxHeight = 160.0;
  final Future<Uint8List> future;
  final String heroTag, sender, time;
  final VoidCallback onRetry;
  const ChatImage({
    super.key,
    required this.future,
    required this.heroTag,
    required this.sender,
    required this.time,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      key: const Key('chat-image-box'),
      width: boxWidth,
      height: boxHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (_, s) {
            if (s.hasData) {
              return GestureDetector(
                onTap: () => openImageViewer(
                  context,
                  bytes: s.data!,
                  tag: heroTag,
                  sender: sender,
                  time: time,
                ),
                child: Hero(
                  tag: heroTag,
                  createRectTween: (begin, end) =>
                      ImageRectTween(begin: begin, end: end),
                  child: Image.memory(
                    s.data!,
                    width: boxWidth,
                    height: boxHeight,
                    fit: BoxFit.cover,
                    cacheWidth: (boxWidth * dpr).round(),
                    gaplessPlayback: true,
                  ),
                ),
              );
            }
            if (s.hasError) {
              return ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('图片加载失败，重试'),
                  ),
                ),
              );
            }
            return const ColoredBox(
              color: Color(0x33223344),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
