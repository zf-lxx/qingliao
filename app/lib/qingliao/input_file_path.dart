//
//  input_file_path.dart
//
//  The UI sends attachments as inputDocument / inputPhoto / inputAudio
//  wrappers around an inputFileLocal (or inputFileId). The send adapter must
//  walk through that wrapper to find the path; reading the wrapper itself
//  looks like an empty message.
//

const List<String> kInputFileNestedKeys = [
  'document',
  'photo',
  'video',
  'audio',
  'voice_note',
  'animation',
  'video_note',
  'sticker',
  'thumbnail',
  'file',
  'background',
];

/// The innermost inputFile* map in [input], or null when none is present.
Map<String, dynamic>? nestedInputFile(Object? input, [int depth = 0]) {
  if (input is! Map || depth > 6) return null;
  final map = Map<String, dynamic>.from(input);
  final type = map['@type']?.toString() ?? '';
  if (type == 'inputFileLocal' ||
      type == 'inputFileId' ||
      type == 'inputFileRemote') {
    return map;
  }
  for (final key in kInputFileNestedKeys) {
    final child = map[key];
    if (child is Map) {
      final found = nestedInputFile(child, depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

/// The local filesystem path on an inputFileLocal, walking wrappers such as
/// inputDocument. Returns null for inputFileId / inputFileRemote / missing
/// paths — callers that can resolve file ids should do so themselves.
String? localPathOfInputFile(Object? input) {
  final file = nestedInputFile(input);
  if (file == null || file['@type'] != 'inputFileLocal') return null;
  final path = file['path']?.toString() ?? '';
  return path.isEmpty ? null : path;
}
