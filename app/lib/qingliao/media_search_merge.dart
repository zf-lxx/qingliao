// Helpers for in-chat media search. The backend exposes image and video as
// separate kinds; a photo-and-video query has to ask for both and merge.


/// Kinds to request for a TDLib-style chat-message filter.
///
/// Photo-and-video is the pair `image` and `video`, never `all` — `all` also
/// matches files and link previews.
List<String> mediaKindsForSearchFilter(String filter) => switch (filter) {
  'searchMessagesFilterPhoto' => const ['image'],
  'searchMessagesFilterVideo' => const ['video'],
  'searchMessagesFilterPhotoAndVideo' => const ['image', 'video'],
  'searchMessagesFilterDocument' => const ['file'],
  'searchMessagesFilterVoiceNote' ||
  'searchMessagesFilterVoiceAndVideoNote' => const ['voice'],
  'searchMessagesFilterUrl' => const ['link'],
  'searchMessagesFilterAudio' => const ['audio'],
  _ => const [],
};

/// Full photo+video count from a media `counts` map. Does not add the length
/// of the current page — that double-counted image+video pages.
int photoAndVideoTotalCount({int? image, int? video, int fallback = 0}) {
  final total = (image ?? 0) + (video ?? 0);
  if (image == null && video == null) return fallback;
  return total;
}

/// Merges two newest-first id-sorted pages and keeps the newest [limit] items.
///
/// [idOf] should return the message id (larger is newer). The cut-off of the
/// kept page is a valid `before` cursor for both source streams.
List<T> mergeNewestMessagePages<T>({
  required List<T> first,
  required List<T> second,
  required int Function(T item) idOf,
  required int limit,
}) {
  if (limit <= 0) return const [];
  final combined = <T>[...first, ...second]
    ..sort((a, b) => idOf(b).compareTo(idOf(a)));
  final seen = <int>{};
  final out = <T>[];
  for (final item in combined) {
    if (!seen.add(idOf(item))) continue;
    out.add(item);
    if (out.length >= limit) break;
  }
  return out;
}

/// Whether a converted chat message is a photo or a playable video.
bool isPhotoOrVideoMessage(Map<String, dynamic> message) {
  final content = message['content'];
  if (content is! Map) return false;
  final type = content['@type']?.toString();
  return type == 'messagePhoto' || type == 'messageVideo';
}
