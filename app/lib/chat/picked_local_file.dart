//
//  picked_local_file.dart
//
//  The system file picker sometimes hands back a content URI, a file: URI, or
//  only in-memory bytes. The send adapter can only upload a real local path.
//

import 'dart:io';
import 'dart:typed_data';

/// A picker result reduced to the fields we need to materialize a local file.
class PickedLocalFile {
  const PickedLocalFile({
    this.path,
    required this.name,
    this.bytes,
    this.readBytes,
    this.readStream,
  });

  final String? path;
  final String name;
  final Uint8List? bytes;
  final Future<Uint8List?> Function()? readBytes;
  final Stream<List<int>>? readStream;
}

/// Whether [path] looks like an Android/iOS content URI the engine cannot open.
bool isContentUriPath(String path) {
  final lower = path.trim().toLowerCase();
  return lower.startsWith('content:');
}

/// A filesystem path the engine can open, or null when [path] is empty,
/// a content URI, or an unparseable file: URI.
String? filesystemPathOf(String? path) {
  final raw = path?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (isContentUriPath(raw)) return null;
  if (raw.toLowerCase().startsWith('file:')) {
    try {
      return Uri.parse(raw).toFilePath();
    } on Object {
      return null;
    }
  }
  return raw;
}

String _safeFileName(String name) {
  final trimmed = name.trim();
  final base = trimmed.isEmpty ? 'file' : trimmed;
  return base.replaceAll(RegExp(r'[\\/]+'), '_');
}

/// Copy the picked file into [directory] when the given path is missing or
/// not a readable filesystem file. Returns a path the engine can upload.
Future<String?> materializePickedLocalPath(
  PickedLocalFile file, {
  required Directory directory,
}) async {
  final existing = filesystemPathOf(file.path);
  if (existing != null) {
    try {
      if (await File(existing).exists()) return existing;
    } on FileSystemException {
      // Fall through and try to copy from bytes / stream.
    }
  }

  Uint8List? data = file.bytes;
  if (data == null || data.isEmpty) {
    if (file.readBytes != null) {
      try {
        data = await file.readBytes!();
      } on Object {
        data = null;
      }
    }
  }
  if ((data == null || data.isEmpty) && file.readStream != null) {
    try {
      final chunks = await file.readStream!.toList();
      final builder = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        builder.add(chunk);
      }
      data = builder.takeBytes();
    } on Object {
      data = null;
    }
  }
  if (data == null || data.isEmpty) return null;

  await directory.create(recursive: true);
  final target = File('${directory.path}/${_safeFileName(file.name)}');
  await target.writeAsBytes(data, flush: true);
  return target.path;
}
