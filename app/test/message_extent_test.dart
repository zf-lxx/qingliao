import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/message_extent.dart';
import 'package:qingliao/tdlib/td_models.dart';

void main() {
  test('a text message stays compact', () {
    final message = ChatMessage(
      id: 1,
      isOutgoing: true,
      text: '哈哈哈',
      date: 1,
      contentType: 'messageText',
    );
    expect(
      estimatedTranscriptMessageExtent(message: message, viewportWidth: 400),
      lessThan(80),
    );
  });

  test('a link preview with large media is much taller than plain text', () {
    final plain = ChatMessage(
      id: 1,
      isOutgoing: true,
      text: 'https://nginx2root.com/',
      date: 1,
      contentType: 'messageText',
    );
    final withPreview = ChatMessage(
      id: 2,
      isOutgoing: true,
      text: 'https://nginx2root.com/',
      date: 1,
      contentType: 'messageText',
      linkPreview: MessageLinkPreview(
        url: 'https://nginx2root.com/',
        displayUrl: 'https://nginx2root.com/',
        siteName: '',
        title:
            'unauthenticated RCE to host root, chained with a kernel exploit.',
        description: '',
        image: TdFileRef(id: 9),
        imageWidth: 1200,
        imageHeight: 675,
        showLargeMedia: true,
      ),
    );
    final textHeight = estimatedTranscriptMessageExtent(
      message: plain,
      viewportWidth: 400,
    );
    final previewHeight = estimatedTranscriptMessageExtent(
      message: withPreview,
      viewportWidth: 400,
    );
    expect(previewHeight, greaterThan(textHeight + 120));
  });

  test('fitContainedSize keeps the aspect ratio and fallback', () {
    expect(
      fitContainedSize(
        width: 200,
        height: 100,
        maxWidth: 100,
        maxHeight: 80,
        fallback: const Size(10, 10),
      ),
      const Size(100, 50),
    );
    expect(
      fitContainedSize(
        width: 0,
        height: 0,
        maxWidth: 100,
        maxHeight: 80,
        fallback: const Size(40, 30),
      ),
      const Size(40, 30),
    );
  });
}
