import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/ql_login_view.dart';
import 'package:qingliao/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final regular = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
  final bold = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc');
  if (regular.existsSync()) {
    final data = ByteData.sublistView(regular.readAsBytesSync());
    await (FontLoader('Noto Sans CJK SC')..addFont(Future.value(data))).load();
  }
  if (bold.existsSync()) {
    final data = ByteData.sublistView(bold.readAsBytesSync());
    await (FontLoader('Noto Sans CJK SC')..addFont(Future.value(data))).load();
  }
}

void main() {
  testWidgets('headless screenshots: P2 login and 暂未开放', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loadFonts();

    const key = Key('shot-boundary');
    Future<void> shot(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('shots/mithka-p2').create(recursive: true);
        await File('shots/mithka-p2/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Widget app(Widget home) {
      return RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'Noto Sans CJK SC',
            extensions: [AppColors.dark],
            scaffoldBackgroundColor: AppColors.dark.background,
          ),
          home: home,
        ),
      );
    }

    await tester.pumpWidget(app(const QlLoginView()));
    await tester.pump(const Duration(milliseconds: 300));
    await shot('01-login');

    await tester.tap(find.text('有邀请码？注册'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot('02-register');

    await tester.tap(find.text('服务器设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot('03-login-server');

    final colors = AppColors.dark;
    await tester.pumpWidget(
      app(
        Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '贴纸',
                    style: TextStyle(
                      fontFamily: 'Noto Sans CJK SC',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '暂未开放',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Noto Sans CJK SC',
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '这一项需要服务端能力，目前还没有接上。不会写入任何设置。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Noto Sans CJK SC',
                            fontSize: 15,
                            color: colors.textSecondary,
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
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shot('04-not-yet');
  });
}
