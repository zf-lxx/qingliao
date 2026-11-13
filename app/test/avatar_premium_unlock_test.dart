import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chats/self_chat.dart';
import 'package:qingliao/profile/profile_photo_policy.dart';
import 'package:qingliao/qingliao/avatar_media.dart';
import 'package:qingliao/settings/account_capabilities.dart';

void main() {
  group('membership gate is gone', () {
    test('capabilities are unlocked without a paid account', () {
      expect(AccountCapabilities.unlocked, isTrue);
    });

    test('animated avatar request is built with no premium argument', () {
      final request = animatedProfilePhotoRequest(path: '/tmp/a.mp4');
      expect(request, isNotNull);
      expect(request!['@type'], 'setProfilePhoto');
      final photo = request['photo'] as Map<String, dynamic>;
      expect(photo['@type'], 'inputChatPhotoAnimation');
      expect(photo['main_frame_timestamp'], 0.0);
    });

    test('an explicitly false isPremium is ignored, not obeyed', () {
      // Regression: the adapter used to return null here, so the picker
      // reported "animated avatars need membership" for every account.
      final request =
          animatedProfilePhotoRequest(isPremium: false, path: '/tmp/a.gif');
      expect(request, isNotNull);
    });

    test('empty path still yields no request', () {
      expect(animatedProfilePhotoRequest(path: ''), isNull);
    });
  });

  group('avatar mime support matches the server allow-list', () {
    test('server-accepted mimes are accepted', () {
      for (final mime in [
        'image/png',
        'image/jpeg',
        'image/webp',
        'image/gif',
        'video/mp4',
        'video/webm',
      ]) {
        expect(isProfileAvatarMime(mime), isTrue, reason: mime);
      }
    });

    test('mimes outside the allow-list are rejected', () {
      for (final mime in ['image/bmp', 'application/pdf', 'text/plain', '']) {
        expect(isProfileAvatarMime(mime), isFalse, reason: mime);
      }
    });

    test('only mp4/webm take the video player path', () {
      expect(avatarMimeUsesVideoPlayer('video/mp4'), isTrue);
      expect(avatarMimeUsesVideoPlayer('VIDEO/WEBM'), isTrue);
      expect(avatarMimeUsesVideoPlayer('image/gif'), isFalse);
      expect(avatarMimeUsesVideoPlayer('image/webp'), isFalse);
    });

    test('gif and webp animate through the image decoder', () {
      expect(avatarMimeIsAnimatedImage('image/gif'), isTrue);
      expect(avatarMimeIsAnimatedImage('image/webp'), isTrue);
      expect(avatarMimeIsAnimatedImage('image/jpeg'), isFalse);
    });
  });

  group('self chat never reaches the list', () {
    test('a direct chat with yourself is hidden', () {
      expect(
        isHiddenSelfChat(meId: 7, peerUserId: 7),
        isTrue,
      );
    });

    test('saved messages stays hidden', () {
      expect(
        isHiddenSelfChat(meId: 7, peerUserId: 7, isSavedMessages: true),
        isTrue,
      );
    });

    test('a chat with somebody else is kept', () {
      expect(isHiddenSelfChat(meId: 7, peerUserId: 8), isFalse);
    });

    test('unknown ids never hide a real conversation', () {
      expect(isHiddenSelfChat(meId: null, peerUserId: 8), isFalse);
      expect(isHiddenSelfChat(meId: 7, peerUserId: null), isFalse);
    });
  });
}
