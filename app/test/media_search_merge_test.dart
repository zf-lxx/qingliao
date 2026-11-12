import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/media_search_merge.dart';

void main() {
  test('photo-and-video asks for image and video, never all', () {
    expect(mediaKindsForSearchFilter('searchMessagesFilterPhotoAndVideo'), [
      'image',
      'video',
    ]);
    expect(
      mediaKindsForSearchFilter('searchMessagesFilterPhotoAndVideo'),
      isNot(contains('all')),
    );
    expect(mediaKindsForSearchFilter('searchMessagesFilterPhoto'), ['image']);
    expect(mediaKindsForSearchFilter('searchMessagesFilterDocument'), ['file']);
  });

  test('photo-and-video totals do not add the page length again', () {
    expect(photoAndVideoTotalCount(image: 2, video: 0), 2);
    expect(photoAndVideoTotalCount(image: 1, video: 1), 2);
    expect(photoAndVideoTotalCount(image: 2, video: 0, fallback: 2), 2);
    expect(photoAndVideoTotalCount(fallback: 2), 2);
  });

  test(
    'merged pages keep the newest limit items and a valid before cursor',
    () {
      final images = [
        {'id': 40, 'kind': 'image'},
        {'id': 20, 'kind': 'image'},
      ];
      final videos = [
        {'id': 30, 'kind': 'video'},
        {'id': 10, 'kind': 'video'},
      ];
      final merged = mergeNewestMessagePages(
        first: images,
        second: videos,
        idOf: (item) => item['id']! as int,
        limit: 3,
      );
      expect(merged.map((item) => item['id']), [40, 30, 20]);
      expect(
        isPhotoOrVideoMessage({
          'content': {'@type': 'messagePhoto'},
        }),
        isTrue,
      );
      expect(
        isPhotoOrVideoMessage({
          'content': {'@type': 'messageVideo'},
        }),
        isTrue,
      );
      expect(
        isPhotoOrVideoMessage({
          'content': {'@type': 'messageDocument'},
        }),
        isFalse,
      );
      expect(
        isPhotoOrVideoMessage({
          'content': {'@type': 'messageText'},
        }),
        isFalse,
      );
    },
  );
}
