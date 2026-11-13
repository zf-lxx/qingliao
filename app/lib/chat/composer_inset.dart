//
//  composer_inset.dart
//
//  The chat page does not resize for the keyboard. That is what Telegram does,
//  and it removes a jump the old arrangement had: Scaffold shrank the body by
//  viewInsets.bottom, so on a cold first open the transcript and composer could
//  shift up once the inset resolved, a frame after the page first painted.
//
//  With no Scaffold resize, the composer is responsible for keeping itself
//  above the keyboard and for clearing the gesture bar. Kept free of widgets so
//  the rule is testable on its own.
//

/// Bottom space the composer must reserve for a given pair of insets.
///
/// The keyboard and the system gesture area occupy the same strip of screen, so
/// they add rather than stack: a phone with a 34dp home indicator and a 300dp
/// keyboard needs 300dp, not 334dp.
double composerBottomInset({
  required double safeArea,
  required double keyboard,
}) {
  final safe = safeArea.isFinite && safeArea > 0 ? safeArea : 0.0;
  final ime = keyboard.isFinite && keyboard > 0 ? keyboard : 0.0;
  return ime > safe ? ime : safe;
}

/// Whether the composer should pad itself rather than paint an overlay.
///
/// A docked panel (emoji, stickers, reply keyboard) already paints its own
/// surface down to the screen edge, so padding the column would leave a gap of
/// unrelated colour above the panel. Those cases extend the panel instead.
bool composerReservesBottomInset({
  required double bottomInset,
  required bool panelSurfaceVisible,
}) => bottomInset > 0 && !panelSurfaceVisible;
