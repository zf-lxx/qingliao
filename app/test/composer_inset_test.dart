//
//  composer_inset_test.dart
//
//  The chat page no longer resizes for the keyboard; the composer reserves the
//  inset instead. These rules keep the field above the IME without stacking the
//  gesture area on top of it, and keep docked panels flush with the screen edge.
//

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/app/stable_system_insets.dart';
import 'package:qingliao/chat/composer_inset.dart';

void main() {
  group('composerBottomInset', () {
    test('no keyboard and no gesture bar reserves nothing', () {
      expect(composerBottomInset(safeArea: 0, keyboard: 0), 0);
    });

    test('the gesture bar alone is reserved', () {
      expect(composerBottomInset(safeArea: 34, keyboard: 0), 34);
    });

    test('the keyboard wins over a smaller gesture bar', () {
      expect(
        composerBottomInset(safeArea: 34, keyboard: 300),
        300,
        reason: 'keyboard and gesture area share the same strip',
      );
    });

    test('the gesture bar wins when the keyboard is smaller', () {
      expect(composerBottomInset(safeArea: 34, keyboard: 12), 34);
    });

    test('insets are not summed', () {
      final both = composerBottomInset(safeArea: 34, keyboard: 300);
      expect(both, isNot(334));
    });

    test('non-finite and negative values are ignored', () {
      expect(
        composerBottomInset(safeArea: double.nan, keyboard: double.infinity),
        0,
      );
      expect(composerBottomInset(safeArea: -10, keyboard: -5), 0);
    });

    test('an infinite keyboard inset does not reserve infinity', () {
      // A broken MediaQuery must not collapse the transcript entirely.
      expect(composerBottomInset(safeArea: 34, keyboard: double.infinity), 34);
    });
  });

  group('composerReservesBottomInset', () {
    test('a plain composer reserves its inset', () {
      expect(
        composerReservesBottomInset(
          bottomInset: 300,
          panelSurfaceVisible: false,
        ),
        isTrue,
      );
    });

    test('a docked panel extends itself instead of padding', () {
      expect(
        composerReservesBottomInset(
          bottomInset: 300,
          panelSurfaceVisible: true,
        ),
        isFalse,
        reason: 'padding above a panel would leave a strip of stray colour',
      );
    });

    test('nothing is reserved when the inset is zero', () {
      expect(
        composerReservesBottomInset(bottomInset: 0, panelSurfaceVisible: false),
        isFalse,
      );
    });
  });

  group('StableSystemInsets', () {
    setUp(StableSystemInsets.debugReset);
    tearDown(StableSystemInsets.debugReset);

    test('a brief zero after a real inset keeps the last value', () {
      expect(StableSystemInsets.holdBottom(34), 34);
      for (var i = 0; i < kTransientZeroInsetFrames; i++) {
        expect(
          StableSystemInsets.holdBottom(0),
          34,
          reason: 'zero frame ${i + 1} of $kTransientZeroInsetFrames',
        );
      }
      expect(
        StableSystemInsets.holdBottom(0),
        0,
        reason:
            'a lasting zero (no gesture bar, or landscape) must be accepted',
      );
    });

    test('zeros during a route transition never clear the cache', () {
      expect(StableSystemInsets.holdBottom(34), 34);
      for (var i = 0; i < kTransientZeroInsetFrames + 8; i++) {
        expect(StableSystemInsets.holdBottom(0, ignoreTransientZero: true), 34);
      }
      // After the transition, a short burst of zeros is still held.
      expect(StableSystemInsets.holdBottom(0), 34);
    });

    test('the first positive inset is used immediately', () {
      expect(StableSystemInsets.holdBottom(0), 0);
      expect(StableSystemInsets.holdBottom(34), 34);
    });

    test('a later positive inset replaces the cache', () {
      expect(StableSystemInsets.holdTop(47), 47);
      expect(StableSystemInsets.holdTop(24), 24);
    });

    testWidgets(
      'a MediaQuery that lags behind the view still uses the view padding',
      (tester) async {
        const dpr = 2.0;
        tester.view.devicePixelRatio = dpr;
        tester.view.padding = const FakeViewPadding(
          bottom: 34 * dpr,
          top: 47 * dpr,
        );
        tester.view.viewPadding = const FakeViewPadding(
          bottom: 34 * dpr,
          top: 47 * dpr,
        );
        addTearDown(tester.view.reset);

        // MediaQuery defaults to zero insets, as a new route may before the
        // real safe area arrives. The FlutterView already has the true values.
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(size: Size(400, 800), devicePixelRatio: dpr),
            child: SizedBox(),
          ),
        );
        final context = tester.element(find.byType(SizedBox));
        expect(StableSystemInsets.measureBottom(context), 34);
        expect(StableSystemInsets.measureTop(context), 47);
        expect(StableSystemInsets.bottomOf(context), 34);
        expect(StableSystemInsets.topOf(context), 47);
      },
    );
  });
}
