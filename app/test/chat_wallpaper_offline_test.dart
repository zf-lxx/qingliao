import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/chat_wallpaper.dart';
import 'package:qingliao/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻聊 has no server-side chat wallpaper store, so the adapter answers
/// setChatBackground / setDefaultBackground with [TdError] `QL_UNSUPPORTED`.
/// These tests pin the fallback: the choice must still be saved on-device and
/// must not surface the generic "chatWallpaperSaveFailed" toast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late Map<String, Object> prefs;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('wallpaper-test');
    prefs = <String, Object>{};
    SharedPreferences.setMockInitialValues(prefs);
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  TdError unsupported(String method) => TdError(<String, dynamic>{
    'code': 400,
    'message': 'QL_UNSUPPORTED: $method',
  });

  ChatWallpaperController controller({
    required List<Map<String, dynamic>> queries,
    Object? thrown,
  }) {
    return ChatWallpaperController(
      preferences: () async {
        final instance = await SharedPreferences.getInstance();
        return instance;
      },
      supportDirectory: () async => support,
      activeSlot: () => 0,
      hasActiveClient: () => true,
      query: (request) async {
        queries.add(request);
        if (thrown != null) throw thrown;
        return <String, dynamic>{'@type': 'ok'};
      },
      subscribe: () => const Stream<Map<String, dynamic>>.empty(),
      listenForUpdates: false,
    );
  }

  group('chat background falls back to the device store', () {
    test('a preset is kept locally when the server has no wallpaper store',
        () async {
      final queries = <Map<String, dynamic>>[];
      final c = controller(
        queries: queries,
        thrown: unsupported('setChatBackground'),
      );

      await c.applyWallpaper(
        42,
        const ChatWallpaper.preset('sky'),
        onlyForSelf: false,
      );

      // The adapter was still asked, so a future backend can take over.
      expect(
        queries.map((q) => q['@type']),
        contains('setChatBackground'),
      );
      // But the fallback persisted the selection for rendering.
      final selected = c.wallpaperFor(42);
      expect(selected, isNotNull);
      expect(selected!.kind, ChatWallpaperKind.preset);
      expect(selected.presetId, 'sky');
    });

    test('the local choice is written to preferences', () async {
      final c1 = controller(
        queries: <Map<String, dynamic>>[],
        thrown: unsupported('setChatBackground'),
      );
      await c1.applyWallpaper(
        7,
        const ChatWallpaper.preset('mint'),
        onlyForSelf: false,
      );
      // The fallback goes through the same local store as the legacy path, so
      // the preset must have reached SharedPreferences and be readable back.
      final instance = await SharedPreferences.getInstance();
      final keys = instance.getKeys().where((k) => k.contains('7'));
      expect(keys, isNotEmpty, reason: 'preset must be written to disk');
      final persisted = keys
          .map((k) => instance.getString(k) ?? '')
          .join(' ');
      expect(persisted, contains('mint'));
    });

    test('a real backend error still propagates', () async {
      final c = controller(
        queries: <Map<String, dynamic>>[],
        thrown: TdError(<String, dynamic>{
          'code': 500,
          'message': 'internal failure',
        }),
      );

      await expectLater(
        c.applyWallpaper(
          42,
          const ChatWallpaper.preset('sky'),
          onlyForSelf: false,
        ),
        throwsA(isA<TdError>()),
      );
    });

    test('clearing a wallpaper also tolerates the missing method', () async {
      final c = controller(
        queries: <Map<String, dynamic>>[],
        thrown: unsupported('deleteChatBackground'),
      );

      await c.applyWallpaper(42, null, onlyForSelf: false);

      expect(c.wallpaperFor(42), isNull);
    });
  });

  group('default (global) background falls back too', () {
    test('a default background is remembered when the server rejects it',
        () async {
      final c = controller(
        queries: <Map<String, dynamic>>[],
        thrown: unsupported('setDefaultBackground'),
      );

      await c.applyDefaultWallpaper(
        const ChatWallpaper.preset('ocean'),
        dark: false,
      );

      final selected = c.defaultWallpaper(dark: false);
      expect(selected, isNotNull);
      expect(selected!.presetId, 'ocean');
    });
  });

  group('a saved background is still there after the chat is reopened', () {
    ChatWallpaperController reopenable({
      required List<Map<String, dynamic>> queries,
    }) {
      return ChatWallpaperController(
        preferences: () async => SharedPreferences.getInstance(),
        supportDirectory: () async => support,
        activeSlot: () => 0,
        hasActiveClient: () => true,
        query: (request) async {
          queries.add(Map<String, dynamic>.from(request));
          switch (request['@type']) {
            case 'setChatBackground':
            case 'setDefaultBackground':
              throw unsupported('setChatBackground');
            case 'getChat':
              return <String, dynamic>{
                '@type': 'chat',
                'id': request['chat_id'],
              };
            case 'getCurrentState':
              return <String, dynamic>{
                '@type': 'updates',
                'updates': <Map<String, dynamic>>[],
              };
            default:
              return <String, dynamic>{'@type': 'ok'};
          }
        },
        subscribe: () => const Stream<Map<String, dynamic>>.empty(),
        listenForUpdates: false,
      );
    }

    test('getChat with no server background does not wipe the local choice',
        () async {
      final first = reopenable(queries: <Map<String, dynamic>>[]);
      await first.applyWallpaper(
        42,
        const ChatWallpaper.preset('sky'),
        onlyForSelf: false,
      );
      await first.load(42);
      expect(first.wallpaperFor(42)?.presetId, 'sky');

      final second = reopenable(queries: <Map<String, dynamic>>[]);
      await second.load(42);
      expect(
        second.wallpaperFor(42)?.presetId,
        'sky',
        reason: 'relaunch must read the preference back',
      );
    });

    test('a default background survives a new controller', () async {
      final first = reopenable(queries: <Map<String, dynamic>>[]);
      await first.applyDefaultWallpaper(
        const ChatWallpaper.preset('ocean'),
        dark: true,
      );

      final second = reopenable(queries: <Map<String, dynamic>>[]);
      await second.loadDefaultWallpaper(dark: true);
      expect(second.defaultWallpaper(dark: true)?.presetId, 'ocean');
    });
  });

  group('chat themes stay unsupported and say so', () {
    test('applyTheme reports a domain error, not QL_UNSUPPORTED', () async {
      final queries = <Map<String, dynamic>>[];
      final c = controller(
        queries: queries,
        thrown: unsupported('setChatTheme'),
      );

      await expectLater(
        c.applyTheme(42, 'some_theme'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
