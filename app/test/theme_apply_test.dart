//
//  theme_apply_test.dart
//
//  Settings > 外观 > 主题 installs a TelegramCloudTheme into ThemeController.
//  These tests drive that path with the real controller and assert the theme
//  actually becomes the active one, because a theme that "applies" without
//  changing the resolved colors looks exactly like a broken button.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/theme/app_theme.dart';
import 'package:qingliao/theme/telegram_cloud_theme.dart';
import 'package:qingliao/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('built-in themes install and resolve', () {
    test('all four built-ins exist and are recognised as built-in', () {
      expect(builtInTelegramCloudThemes, hasLength(4));
      for (final theme in builtInTelegramCloudThemes) {
        expect(theme.isBuiltIn, isTrue, reason: theme.slug);
        expect(theme.slug, startsWith('builtin:'));
      }
    });

    test('a light theme becomes the active light theme', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final classic = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:classic',
      );

      // Before: nothing installed.
      expect(controller.cloudThemeFor(Brightness.light), isNull);

      controller.installCloudTheme(classic, brightness: Brightness.light);

      final active = controller.cloudThemeFor(Brightness.light);
      expect(active, isNotNull, reason: 'theme did not become active');
      expect(active!.slug, 'builtin:classic');
      // A light theme must not leak into dark.
      expect(controller.cloudThemeFor(Brightness.dark), isNull);
    });

    test('a dark theme becomes the active dark theme only', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final night = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:night',
      );

      controller.installCloudTheme(night, brightness: Brightness.dark);

      expect(controller.cloudThemeFor(Brightness.dark)?.slug, 'builtin:night');
      expect(controller.cloudThemeFor(Brightness.light), isNull);
    });

    test('installing records the theme in the installed list', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final day = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:day',
      );

      controller.installCloudTheme(day, brightness: Brightness.light);

      final slugs = controller.installedCloudThemes.map((t) => t.slug);
      expect(slugs, contains('builtin:day'));
    });

    test('the choice survives a controller restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = ThemeController(prefs);
      final dark = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:dark',
      );
      first.installCloudTheme(dark, brightness: Brightness.light);
      // Persisting is async; give the write a turn.
      await Future<void>.delayed(Duration.zero);

      final restarted = ThemeController(prefs);
      expect(restarted.cloudThemeFor(Brightness.light)?.slug, 'builtin:dark');
    });
  });

  group('replacing a theme swaps rather than stacks', () {
    test('installing a second light theme replaces the first', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final classic = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:classic',
      );
      final day = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:day',
      );

      controller.installCloudTheme(classic, brightness: Brightness.light);
      controller.installCloudTheme(day, brightness: Brightness.light);

      expect(controller.cloudThemeFor(Brightness.light)?.slug, 'builtin:day');
    });

    test('light and dark themes coexist', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final day = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:day',
      );
      final night = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:night',
      );

      controller.installCloudTheme(day, brightness: Brightness.light);
      controller.installCloudTheme(night, brightness: Brightness.dark);

      expect(controller.cloudThemeFor(Brightness.light)?.slug, 'builtin:day');
      expect(controller.cloudThemeFor(Brightness.dark)?.slug, 'builtin:night');
    });
  });

  group('theming can be switched off', () {
    test('disabling theming hides the installed theme', () async {
      final controller = ThemeController(await SharedPreferences.getInstance());
      final classic = builtInTelegramCloudThemes.firstWhere(
        (t) => t.slug == 'builtin:classic',
      );
      controller.installCloudTheme(classic, brightness: Brightness.light);
      expect(controller.cloudThemeFor(Brightness.light), isNotNull);

      controller.themingEnabled = false;

      expect(
        controller.cloudThemeFor(Brightness.light),
        isNull,
        reason: 'themingEnabled=false must stop the theme being used',
      );
    });
  });

  // Applying a theme that produces the same colors as the default looks
  // exactly like a broken button. The built-in light themes shipped pure white
  // backgrounds, which matched the app default, so switching to them changed
  // nothing on screen. Each theme must now be visibly different.
  group('every built-in theme is visibly distinct from the default', () {
    Future<AppColors> resolved(TelegramCloudTheme theme) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller =
          ThemeController(await SharedPreferences.getInstance());
      final target = theme.isDark ? Brightness.dark : Brightness.light;
      controller.installCloudTheme(theme, brightness: target);
      return controller.uiColorsFor(target);
    }

    for (final theme in builtInTelegramCloudThemes) {
      test('${theme.slug} changes the background', () async {
        final before = theme.isDark ? AppColors.dark : AppColors.light;
        final after = await resolved(theme);
        expect(
          after.background,
          isNot(before.background),
          reason: '${theme.slug} would be indistinguishable from the default',
        );
      });

      test('${theme.slug} ships an outgoing bubble colour', () async {
        expect(theme.outgoingColor, isNotNull, reason: theme.slug);
      });
    }
  });
}
