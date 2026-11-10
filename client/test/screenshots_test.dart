import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';

import 'desktop_fonts.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/core/api.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'headless Flutter desktop renderer: login, cached real dialogs, chat and profile',
    (tester) async {
      tester.view.physicalSize = const Size(432, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadDesktopFonts();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      sqfliteFfiInit();
      final store = await tester.runAsync(
        () => LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      );
      final engine = ChatEngine(store!, MemoryVault());
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
          await Directory('shots').create(recursive: true);
          await File('shots/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: QingliaoApp(engine: engine),
        ),
      );
      await shot('01-login-desktop');
      final fixture = obj(
        jsonDecode(File('artifacts/screens-state.json').readAsStringSync()),
      );
      engine.session = {
        'user_id': fixture['user_id'],
        'server': 'http://127.0.0.1:1',
      };
      engine.api = ChatApi('http://127.0.0.1:1');
      engine.restore(obj(fixture['state']));
      engine.privacy = obj(fixture['privacy']);
      engine.users.addAll(
        obj(fixture['users']).map((k, v) => MapEntry(k, obj(v))),
      );
      engine.pins.addAll(
        obj(fixture['pins']).map((k, v) => MapEntry(k, objects(v))),
      );
      engine.reactions.addAll(
        obj(fixture['reactions']).map((k, v) => MapEntry(k, objects(v))),
      );
      // Disconnected cached data is explicitly shown as offline, never staged live.
      engine.online = false;
      engine.suspended = true;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: QingliaoApp(key: UniqueKey(), engine: engine),
        ),
      );
      await shot('02-dialogs-desktop');
      await tester.tap(find.text('阿澈').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await shot('03-chat-desktop');
      expect(find.byKey(const Key('composer')), findsOneWidget);
      expect(find.text('编辑后的正文', findRichText: true), findsWidgets);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('个人资料'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await shot('04-profile-desktop');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.disconnect();
      engine.closed = true;
      await tester.runAsync(() async {
        engine.api?.close();
        await store.close();
      });
      debugDefaultTargetPlatformOverride = null;
    },
    skip: !File('artifacts/screens-state.json').existsSync(),
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
