import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/chat_back_navigation.dart';

void main() {
  test('first back dismisses the composer when it is focused', () {
    expect(
      nextChatBackAction(
        searchActive: false,
        composerFocused: true,
        viewInsetsBottom: 0,
      ),
      ChatBackAction.dismissComposer,
    );
    expect(
      chatBackShouldLeave(
        searchActive: false,
        composerFocused: true,
        viewInsetsBottom: 0,
      ),
      isFalse,
    );
  });

  test('first back dismisses a visible IME even without focus', () {
    expect(
      nextChatBackAction(
        searchActive: false,
        composerFocused: false,
        viewInsetsBottom: 320,
      ),
      ChatBackAction.dismissComposer,
    );
  });

  test('a tiny inset is not treated as a visible IME', () {
    expect(
      nextChatBackAction(
        searchActive: false,
        composerFocused: false,
        viewInsetsBottom: 4,
      ),
      ChatBackAction.leaveChat,
    );
  });

  test('after the composer is dismissed, back leaves the chat', () {
    expect(
      nextChatBackAction(
        searchActive: false,
        composerFocused: false,
        viewInsetsBottom: 0,
      ),
      ChatBackAction.leaveChat,
    );
    expect(
      chatBackShouldLeave(
        searchActive: false,
        composerFocused: false,
        viewInsetsBottom: 0,
      ),
      isTrue,
    );
  });

  test('search closes before the composer or the chat', () {
    expect(
      nextChatBackAction(
        searchActive: true,
        composerFocused: true,
        viewInsetsBottom: 320,
      ),
      ChatBackAction.closeSearch,
    );
    expect(
      nextChatBackAction(
        searchActive: true,
        composerFocused: false,
        viewInsetsBottom: 0,
      ),
      ChatBackAction.closeSearch,
    );
  });
}
