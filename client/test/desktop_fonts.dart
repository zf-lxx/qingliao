import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qingliao/ui/theme/desktop_fonts.dart' as app;

/// Tests force Linux so ChatSans is selected even on a Linux host pretending
/// to be another platform. MaterialIcons still load from Flutter assets.
Future<void> loadDesktopFonts() async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await app.loadDesktopFonts();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
