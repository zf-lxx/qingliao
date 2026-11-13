//
//  audio_message_send_test.dart
//
//  Picking an audio file in the attachment sheet sent inputMessageAudio, which
//  the adapter had no branch for: _draftContent returned null and the user saw
//  "轻聊拒绝发送此消息 / message_empty" for every music file. The backend has
//  no audio kind, so the adapter maps it to a document while keeping the track
//  title and performer.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/avatar_media.dart';

void main() {
  group('audio files resolve to an audio MIME', () {
    test('common music extensions map to audio/*', () {
      const expected = {
        'song.mp3': 'audio/mpeg',
        'track.m4a': 'audio/mp4',
        'clip.aac': 'audio/aac',
        'voice.ogg': 'audio/ogg',
        'lossless.flac': 'audio/flac',
        'recording.wav': 'audio/wav',
        'memo.amr': 'audio/amr',
      };
      expected.forEach((path, mime) {
        expect(uploadMimeForPath(path), mime, reason: path);
      });
    });

    test('an upper-case extension still resolves', () {
      expect(uploadMimeForPath('/tmp/Song.MP3'), 'audio/mpeg');
    });

    test('a file without an extension falls back to server sniffing', () {
      expect(uploadMimeForPath('/tmp/no-extension'), '');
    });

    test('audio is not confused with video or image', () {
      expect(uploadMimeForPath('a.mp3'), isNot(startsWith('video/')));
      expect(uploadMimeForPath('a.ogg'), isNot(startsWith('image/')));
    });
  });
}
