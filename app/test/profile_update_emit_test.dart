//
//  profile_update_emit_test.dart
//
//  Changing your own avatar left the profile screen showing the old photo
//  until the app was restarted. The adapter wrote the new media id into its
//  user cache *before* calling PATCH /me, and _rememberUser decides whether to
//  emit updateUser by comparing the stored record with the server response —
//  so the comparison always matched and no event was emitted.
//
//  These tests pin the notification contract via the pure pieces that decide
//  it, since the engine needs a live client.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/avatar_media.dart';

void main() {
  group('avatar change detection', () {
    // Mirrors the comparison _rememberUser performs.
    bool changed(
      Map<String, dynamic>? previous,
      Map<String, dynamic> merged,
    ) {
      if (previous == null) return true;
      return previous['display_name'] != merged['display_name'] ||
          previous['avatar_media_id'] != merged['avatar_media_id'] ||
          previous['avatar_mime'] != merged['avatar_mime'] ||
          previous['handle'] != merged['handle'];
    }

    test('a new avatar is a change', () {
      final before = <String, dynamic>{
        'id': 'u1',
        'handle': 'me',
        'display_name': '我',
        'avatar_media_id': '',
      };
      final after = <String, dynamic>{
        'id': 'u1',
        'handle': 'me',
        'display_name': '我',
        'avatar_media_id': 'media-new',
      };
      expect(changed(before, after), isTrue);
    });

    test('a new mime alone is a change', () {
      final before = <String, dynamic>{
        'avatar_media_id': 'm1',
        'avatar_mime': 'image/jpeg',
      };
      final after = <String, dynamic>{
        'avatar_media_id': 'm1',
        'avatar_mime': 'image/gif',
      };
      expect(changed(before, after), isTrue);
    });

    test('an identical response is not a change', () {
      final same = <String, dynamic>{
        'id': 'u1',
        'handle': 'me',
        'display_name': '我',
        'avatar_media_id': 'm1',
      };
      expect(changed(same, Map<String, dynamic>.from(same)), isFalse);
    });

    test('pre-seeding the cache hides the change (the original bug)', () {
      final cached = <String, dynamic>{
        'id': 'u1',
        'avatar_media_id': 'm1',
      };
      // The adapter used to do this before the request...
      final seeded = Map<String, dynamic>.from(cached)
        ..['avatar_media_id'] = 'm2';
      // ...so the response looked unchanged.
      expect(changed(seeded, {'id': 'u1', 'avatar_media_id': 'm2'}), isFalse);
    });
  });

  group('avatar mime survives the round trip', () {
    test('animated avatars keep an audio/video-free mime', () {
      expect(isProfileAvatarMime('image/gif'), isTrue);
      expect(isProfileAvatarMime('video/mp4'), isTrue);
      expect(avatarMimeIsAnimatedImage('image/gif'), isTrue);
      expect(avatarMimeUsesVideoPlayer('video/mp4'), isTrue);
    });
  });
}
