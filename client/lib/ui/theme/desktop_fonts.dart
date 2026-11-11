import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Linux/desktop only: register OS Noto CJK + emoji as ChatSans/ChatEmoji.
/// Never bundled in the Android APK. Missing files are ignored so Android
/// and CI without those packages still start.
Future<void> loadDesktopFonts() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return;
  }
  for (final font in [
    ('ChatSans', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
    ('ChatEmoji', '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'),
  ]) {
    final file = File(font.$2);
    if (!file.existsSync()) continue;
    final data = ByteData.sublistView(file.readAsBytesSync());
    await (FontLoader(font.$1)..addFont(Future.value(data))).load();
  }
}
