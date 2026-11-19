import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/picked_local_file.dart';

void main() {
  test('content URIs are not filesystem paths', () {
    expect(isContentUriPath('content://media/external/file/1'), isTrue);
    expect(filesystemPathOf('content://media/external/file/1'), isNull);
    expect(filesystemPathOf('/tmp/doc.pdf'), '/tmp/doc.pdf');
    expect(filesystemPathOf('file:///tmp/doc.pdf'), '/tmp/doc.pdf');
    expect(filesystemPathOf(''), isNull);
    expect(filesystemPathOf(null), isNull);
  });

  test('an existing filesystem path is reused', () async {
    final directory = await Directory.systemTemp.createTemp('ql-pick-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/notes.txt');
    await file.writeAsString('hello');

    final path = await materializePickedLocalPath(
      PickedLocalFile(path: file.path, name: 'notes.txt'),
      directory: directory,
    );
    expect(path, file.path);
  });

  test('bytes are written when the path is a content URI', () async {
    final directory = await Directory.systemTemp.createTemp('ql-pick-');
    addTearDown(() => directory.delete(recursive: true));

    final path = await materializePickedLocalPath(
      PickedLocalFile(
        path: 'content://downloads/all/99',
        name: 'report.pdf',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
      directory: directory,
    );
    expect(path, '${directory.path}/report.pdf');
    expect(await File(path!).readAsBytes(), [1, 2, 3, 4]);
  });

  test('a cancelled or empty pick yields no path', () async {
    final directory = await Directory.systemTemp.createTemp('ql-pick-');
    addTearDown(() => directory.delete(recursive: true));
    final path = await materializePickedLocalPath(
      const PickedLocalFile(name: 'empty.bin'),
      directory: directory,
    );
    expect(path, isNull);
  });
}
