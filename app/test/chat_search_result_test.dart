import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/chat_search_result_presentation.dart';
import 'package:qingliao/l10n/app_localizations.dart';
import 'package:qingliao/tdlib/td_models.dart';

void main() {
  test(
    'empty captions use a type name, not the generic message placeholder',
    () {
      final placeholder = AppStrings.t(
        AppStringKeys.chatSearchMessageResultLabel,
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 1,
            isOutgoing: false,
            text: '',
            date: 1,
            image: TdFileRef(id: 9),
          ),
        ),
        AppStrings.t(AppStringKeys.composerImagePreview),
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 2,
            isOutgoing: false,
            text: '',
            date: 1,
            video: TdFileRef(id: 8),
          ),
        ),
        AppStrings.t(AppStringKeys.chatVideoPlaceholder),
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 3,
            isOutgoing: false,
            text: '',
            date: 1,
            document: MessageDocument(
              fileName: 'notes.pdf',
              size: 12,
              ext: 'PDF',
              file: null,
            ),
          ),
        ),
        contains('notes.pdf'),
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 4,
            isOutgoing: false,
            text: '',
            date: 1,
            voice: MessageVoice(duration: 3, file: null),
          ),
        ),
        AppStrings.t(AppStringKeys.composerVoicePreview),
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(id: 5, isOutgoing: false, text: '', date: 1),
        ),
        placeholder,
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 6,
            isOutgoing: false,
            text: 'caption here',
            date: 1,
            image: TdFileRef(id: 9),
          ),
        ),
        'caption here',
      );
      expect(
        chatSearchResultSnippet(
          ChatMessage(
            id: 7,
            isOutgoing: false,
            text: placeholder,
            date: 1,
            image: TdFileRef(id: 9),
          ),
        ),
        isNot(placeholder),
      );
    },
  );

  test('match counter is 1-based and never reports 0 when hits exist', () {
    expect(chatSearchMatchPosition(activeIndex: -1, resultCount: 0), 0);
    expect(chatSearchMatchPosition(activeIndex: -1, resultCount: 2), 1);
    expect(chatSearchMatchPosition(activeIndex: 0, resultCount: 2), 1);
    expect(chatSearchMatchPosition(activeIndex: 1, resultCount: 2), 2);
  });
}
