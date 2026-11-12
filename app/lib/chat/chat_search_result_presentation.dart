import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';

/// Label for a search hit that has no useful caption, so the row never falls
/// back to the generic "[消息]" placeholder.
String chatSearchResultSnippet(ChatMessage message) {
  final caption = message.text.trim();
  final placeholder = AppStrings.t(AppStringKeys.chatSearchMessageResultLabel);
  final usefulCaption =
      caption.isNotEmpty &&
      caption != placeholder &&
      caption != AppStrings.t(AppStringKeys.composerImagePreview) &&
      caption != AppStrings.t(AppStringKeys.chatVideoPlaceholder);
  if (usefulCaption) return caption.replaceAll('\n', ' ');
  if (message.video != null) {
    return AppStrings.t(AppStringKeys.chatVideoPlaceholder);
  }
  if (message.image != null) {
    return AppStrings.t(AppStringKeys.composerImagePreview);
  }
  if (message.document != null) {
    final name = message.document!.fileName.trim();
    if (name.isNotEmpty) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {'value1': name});
    }
    return AppStrings.t(AppStringKeys.searchTabFiles);
  }
  if (message.voice != null) {
    return AppStrings.t(AppStringKeys.composerVoicePreview);
  }
  if (message.music != null) {
    final title = message.music!.title.trim();
    return title.isNotEmpty
        ? title
        : AppStrings.t(AppStringKeys.searchTabMusic);
  }
  if (message.linkPreview != null) {
    final title = message.linkPreview!.title.trim();
    if (title.isNotEmpty) return title;
    return AppStrings.t(AppStringKeys.searchTabLinks);
  }
  return placeholder;
}

/// 1-based cursor among [resultCount] hits. Zero only when there are no hits;
/// an unselected list still reports 1 so the counter never shows "第 0".
int chatSearchMatchPosition({
  required int activeIndex,
  required int resultCount,
}) {
  if (resultCount <= 0) return 0;
  if (activeIndex < 0) return 1;
  return activeIndex + 1;
}
