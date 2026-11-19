//
//  input_file_path_test.dart
//
//  Sending a document from the + / 文件 action wraps the local file in
//  inputDocument. The send adapter used to read that wrapper as if it were
//  the file, get a null path, and reject the message as MESSAGE_EMPTY.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/outgoing_attachment.dart';
import 'package:qingliao/qingliao/input_file_path.dart';

void main() {
  test('a bare inputFileLocal keeps its path', () {
    expect(
      localPathOfInputFile({
        '@type': 'inputFileLocal',
        'path': '/tmp/notes.txt',
      }),
      '/tmp/notes.txt',
    );
  });

  test('inputDocument wrapping an inputFileLocal yields the path', () {
    final content = attachmentInputMessageContent(
      const OutgoingAttachment(
        path: '/tmp/report.pdf',
        kind: OutgoingAttachmentKind.document,
        fileName: 'report.pdf',
      ),
    );
    expect(content['@type'], 'inputMessageDocument');
    expect(localPathOfInputFile(content['document']), '/tmp/report.pdf');
  });

  test('inputPhoto and inputAudio wrappers also yield the path', () {
    final photo = attachmentInputMessageContent(
      const OutgoingAttachment(
        path: '/tmp/shot.jpg',
        kind: OutgoingAttachmentKind.photo,
      ),
    );
    final audio = attachmentInputMessageContent(
      const OutgoingAttachment(
        path: '/tmp/track.mp3',
        kind: OutgoingAttachmentKind.audio,
      ),
    );
    expect(localPathOfInputFile(photo['photo']), '/tmp/shot.jpg');
    expect(localPathOfInputFile(audio['audio']), '/tmp/track.mp3');
  });

  test('an empty path or a file id is not a local path', () {
    expect(
      localPathOfInputFile({'@type': 'inputFileLocal', 'path': ''}),
      isNull,
    );
    expect(localPathOfInputFile({'@type': 'inputFileId', 'id': 7}), isNull);
  });
}
