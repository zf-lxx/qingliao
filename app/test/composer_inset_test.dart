//
//  composer_inset_test.dart
//
//  The chat page no longer resizes for the keyboard; the composer reserves the
//  inset instead. These rules keep the field above the IME without stacking the
//  gesture area on top of it, and keep docked panels flush with the screen edge.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/composer_inset.dart';

void main() {
  group('composerBottomInset', () {
    test('no keyboard and no gesture bar reserves nothing', () {
      expect(
        composerBottomInset(safeArea: 0, keyboard: 0),
        0,
      );
    });

    test('the gesture bar alone is reserved', () {
      expect(
        composerBottomInset(safeArea: 34, keyboard: 0),
        34,
      );
    });

    test('the keyboard wins over a smaller gesture bar', () {
      expect(
        composerBottomInset(safeArea: 34, keyboard: 300),
        300,
        reason: 'keyboard and gesture area share the same strip',
      );
    });

    test('the gesture bar wins when the keyboard is smaller', () {
      expect(
        composerBottomInset(safeArea: 34, keyboard: 12),
        34,
      );
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
      expect(
        composerBottomInset(safeArea: 34, keyboard: double.infinity),
        34,
      );
    });
  });

  group('composerReservesBottomInset', () {
    test('a plain composer reserves its inset', () {
      expect(
        composerReservesBottomInset(bottomInset: 300, panelSurfaceVisible: false),
        isTrue,
      );
    });

    test('a docked panel extends itself instead of padding', () {
      expect(
        composerReservesBottomInset(bottomInset: 300, panelSurfaceVisible: true),
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
}
