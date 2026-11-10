import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Linux screenshot-only fonts, read from the box OS. No font data in pubspec,
/// no font binaries bundled in the Android release. Tests need fonts-noto-cjk
/// and fonts-noto-color-emoji installed on their Linux runner.
Future<void> loadDesktopFonts() async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  for (final font in [
    ('ChatSans', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
    ('ChatEmoji', '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'),
  ]) {
    final data = ByteData.sublistView(File(font.$2).readAsBytesSync());
    await (FontLoader(font.$1)..addFont(Future.value(data))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
