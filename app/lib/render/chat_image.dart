import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Fixed 240×160 box so the list never jumps when bytes arrive.
class ChatImageBox extends StatelessWidget {
  static const boxWidth = 240.0, boxHeight = 160.0;
  final Future<Uint8List>? future;
  final Widget? image;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  const ChatImageBox({
    super.key,
    this.future,
    this.image,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget body;
    if (image != null) {
      body = image!;
    } else if (future != null) {
      body = FutureBuilder<Uint8List>(
        future: future,
        builder: (_, s) {
          if (s.hasData) {
            return Image.memory(
              s.data!,
              width: boxWidth,
              height: boxHeight,
              fit: BoxFit.cover,
              cacheWidth: (boxWidth * dpr).round(),
              gaplessPlayback: true,
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
          return const _Placeholder();
        },
      );
    } else {
      body = const _Placeholder();
    }
    return SizedBox(
      key: const Key('chat-image-box'),
      width: boxWidth,
      height: boxHeight,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: body),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0x33223344),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// Stable layout box used when a photo has no width/height yet.
Size unknownImagePlaceholderSize({
  required double availableWidth,
  double maxHeight = 320,
}) {
  const w = ChatImageBox.boxWidth;
  const h = ChatImageBox.boxHeight;
  if (availableWidth >= w) return const Size(w, h);
  final scale = (availableWidth / w).clamp(0.0, 1.0);
  return Size(availableWidth.clamp(1, w), (h * scale).clamp(1, h));
}
