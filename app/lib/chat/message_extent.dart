//
//  message_extent.dart
//
//  A first-pass height used to place the transcript before every bubble has
//  measured itself. Underestimating a tall last message (especially a link
//  preview with a reserved image) means the first correction jumps the window
//  up above the composer.
//

import 'dart:math' as math;
import 'dart:ui' show Size;

import '../tdlib/td_models.dart';

const double kLinkPreviewLargeMediaMaxHeight = 180;
const double kLinkPreviewSmallMediaMaxHeight = 120;

/// Fit a source size into [maxWidth] x [maxHeight], keeping aspect ratio.
Size fitContainedSize({
  required int? width,
  required int? height,
  required double maxWidth,
  required double maxHeight,
  required Size fallback,
}) {
  final w = width, h = height;
  if (w == null || h == null || w <= 0 || h <= 0) return fallback;
  final aspect = w / h;
  var dw = maxWidth;
  var dh = dw / aspect;
  if (dh > maxHeight) {
    dh = maxHeight;
    dw = dh * aspect;
  }
  return Size(dw, dh);
}

/// Reserved height of a link-preview card, including its media slot.
double estimatedLinkPreviewExtent(
  MessageLinkPreview preview,
  double viewportWidth,
) {
  var height = 16.0;
  if (preview.siteName.isNotEmpty) height += 16;
  if (preview.title.isNotEmpty) height += 36;
  if (preview.description.isNotEmpty) height += 48;
  if (preview.displayUrl.isNotEmpty) height += 16;
  if (preview.hasMedia) {
    final large =
        preview.showLargeMedia || preview.type == 'linkPreviewTypePhoto';
    final maxWidth = math.max(1.0, viewportWidth * 0.75 - 12);
    final width = large ? maxWidth : math.min(maxWidth, 210.0);
    final size = fitContainedSize(
      width: preview.imageWidth,
      height: preview.imageHeight,
      maxWidth: width,
      maxHeight: large
          ? kLinkPreviewLargeMediaMaxHeight
          : kLinkPreviewSmallMediaMaxHeight,
      fallback: Size(width, large ? 140 : 96),
    );
    height += size.height;
  }
  return height;
}

/// A cheap height for one transcript message, used only for the opening jump.
double estimatedTranscriptMessageExtent({
  required ChatMessage message,
  required double viewportWidth,
  bool isGroup = false,
}) {
  if (message.animatedSticker != null || message.videoSticker != null) {
    return 180;
  }
  if (message.image != null || message.video != null) {
    final h = message.imageHeight ?? 180;
    final w = message.imageWidth ?? 180;
    final mediaMax = math.min(viewportWidth * 0.75, 310.0);
    final scaled = w <= 0 ? 180.0 : mediaMax * h / w;
    return scaled.clamp(120.0, 310.0) + 16;
  }
  if (message.document != null ||
      message.music != null ||
      message.voice != null ||
      message.location != null ||
      message.isCall) {
    return 78;
  }
  if (message.diceEmoji != null || message.stickerFileId != null) {
    return 94;
  }
  final text = message.text.trim();
  final charsPerLine = math.max(10, (viewportWidth * 0.52 / 15).floor());
  final lines = text.isEmpty
      ? 1
      : (text.length / charsPerLine).ceil().clamp(1, 8);
  final sender = isGroup && !message.isOutgoing ? 18.0 : 0.0;
  final reply = message.replyToMessageId != null ? 42.0 : 0.0;
  final buttons = message.buttonRows.isNotEmpty
      ? message.buttonRows.length * 38.0
      : 0.0;
  var extent = 30 + sender + reply + lines * 22.0 + buttons;
  final preview = message.linkPreview;
  if (preview != null) {
    extent += estimatedLinkPreviewExtent(preview, viewportWidth);
  }
  return extent;
}
