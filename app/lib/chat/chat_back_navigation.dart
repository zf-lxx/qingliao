/// Decides what a Back press should do in an open conversation.
enum ChatBackAction {
  /// Close in-chat search first, even if the composer or IME is also open.
  closeSearch,

  /// Unfocus the composer and hide the IME, without leaving the chat.
  dismissComposer,

  /// Leave the conversation using the existing exit path.
  leaveChat,
}

/// Threshold for treating [viewInsetsBottom] as a visible IME, in logical
/// pixels. A few pixels of inset can appear from system bars or rounding.
const double kChatImeVisibleThreshold = 8;

ChatBackAction nextChatBackAction({
  required bool searchActive,
  required bool composerFocused,
  required double viewInsetsBottom,
  double imeVisibleThreshold = kChatImeVisibleThreshold,
}) {
  if (searchActive) return ChatBackAction.closeSearch;
  if (composerFocused || viewInsetsBottom > imeVisibleThreshold) {
    return ChatBackAction.dismissComposer;
  }
  return ChatBackAction.leaveChat;
}

bool chatBackShouldLeave({
  required bool searchActive,
  required bool composerFocused,
  required double viewInsetsBottom,
  double imeVisibleThreshold = kChatImeVisibleThreshold,
}) =>
    nextChatBackAction(
      searchActive: searchActive,
      composerFocused: composerFocused,
      viewInsetsBottom: viewInsetsBottom,
      imeVisibleThreshold: imeVisibleThreshold,
    ) ==
    ChatBackAction.leaveChat;
