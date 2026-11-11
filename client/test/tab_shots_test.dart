import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/storage.dart';
import 'package:qingliao/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'desktop_fonts.dart';
import 'engine_live_test.dart' show MemoryVault;
import 'unread_test.dart' show HistoryEngine;

void main() {
  testWidgets('capture chat / contacts / settings / profile tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadDesktopFonts();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final engine = HistoryEngine(store, MemoryVault())
      ..session = {
        'user_id': 'me',
        'server': 'https://chat.example.com',
        'access_token': 't',
      }
      ..online = true
      ..me = {
        'id': 'me',
        'handle': 'qingliao',
        'display_name': '轻聊用户',
      }
      ..privacy = {
        'read_receipts_enabled': true,
        'global_read_receipts_enabled': true,
        'effective': true,
      }
      ..badge = 3;
    engine.users.addAll({
      'peer': {
        'id': 'peer',
        'handle': 'ache',
        'display_name': '阿澈',
        'online': true,
      },
      'bot': {
        'id': 'bot',
        'handle': 'groupbot',
        'display_name': '内测助手',
        'online': false,
      },
    });
    engine.dialogs['d1'] = {
      'id': 'd1',
      'kind': 'direct',
      'display_title': '阿澈',
      'unread_count': 2,
      'unread_mention_count': 0,
      'last_activity': 3,
      'notification_mute_until': 0,
      'pinned_order': 0,
      'last_message': {
        'text': '今晚继续测试',
        'kind': 'text',
        'sender_id': 'peer',
        'created_at': '2026-11-10T15:46:00Z',
      },
      'draft': {'text': '跨端草稿'},
    };
    engine.dialogs['d2'] = {
      'id': 'd2',
      'kind': 'group',
      'title': '轻聊 · 内测小组',
      'unread_count': 1,
      'unread_mention_count': 1,
      'last_activity': 2,
      'notification_mute_until': 9999999999,
      'pinned_order': 0,
      'last_message': {
        'text': '今晚继续测试',
        'kind': 'text',
        'sender_id': 'bot',
        'created_at': '2026-11-10T14:00:00Z',
      },
      'draft': {'text': '今晚继续测试'},
    };
    engine.messages['m1'] = {
      'id': 'm1',
      'conversation_id': 'd1',
      'conversation_seq': 1,
      'sender_id': 'me',
      'kind': 'text',
      'text': '客户端 → 第二账号',
      'created_at': '2026-11-10T15:46:00Z',
      'deleted': false,
      'status': 'stored',
    };
    engine.messages['m2'] = {
      'id': 'm2',
      'conversation_id': 'd1',
      'conversation_seq': 2,
      'sender_id': 'peer',
      'kind': 'text',
      'text': '第二账号 → 客户端',
      'created_at': '2026-11-10T15:46:10Z',
      'deleted': false,
      'status': 'stored',
    };
    engine.messages['m3'] = {
      'id': 'm3',
      'conversation_id': 'd1',
      'conversation_seq': 3,
      'sender_id': 'me',
      'kind': 'text',
      'text': '编辑后的正文',
      'edited_at': '2026-11-10T15:47:00Z',
      'created_at': '2026-11-10T15:46:20Z',
      'deleted': false,
      'status': 'stored',
    };
    engine.messages['m4'] = {
      'id': 'm4',
      'conversation_id': 'd1',
      'conversation_seq': 4,
      'sender_id': 'peer',
      'kind': 'text',
      'text': '看这个 https://example.com',
      'entities': [
        {
          'type': 'url',
          'offset': 4,
          'length': 19,
        },
      ],
      'link_preview': {
        'url': 'https://example.com',
        'site_name': 'example.com',
        'title': 'Example Domain',
        'description': 'This domain is for use in illustrative examples.',
      },
      'created_at': '2026-11-10T15:48:00Z',
      'deleted': false,
      'status': 'stored',
    };

    const key = Key('shot-boundary');
    Future<void> shot(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('shots').create(recursive: true);
        await File('shots/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: QingliaoApp(engine: engine),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await shot('tab-chats');

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    await shot('tab-contacts');

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await shot('tab-settings');

    await tester.tap(find.text('个人资料'));
    await tester.pumpAndSettle();
    await shot('tab-profile');

    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    await shot('page-edit-profile');

    await tester.tap(find.byTooltip('Back').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿澈').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await shot('page-chat');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await engine.shutdown();
    await tester.runAsync(store.close);
    debugDefaultTargetPlatformOverride = null;
  });
}
