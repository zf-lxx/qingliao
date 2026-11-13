import 'dart:io';

/// MIME helpers for a user's own profile photo, including short looping video.
const profileAvatarMimes = <String>{
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
  'video/mp4',
  'video/webm',
};

bool isProfileAvatarMime(String mime) =>
    profileAvatarMimes.contains(mime.toLowerCase());

/// Video avatars need the motion player; gif/webp stills animate via the image decoder.
bool avatarMimeUsesVideoPlayer(String mime) {
  final value = mime.toLowerCase();
  return value == 'video/mp4' || value == 'video/webm';
}

bool avatarMimeIsAnimatedImage(String mime) {
  final value = mime.toLowerCase();
  return value == 'image/gif' || value == 'image/webp';
}

String avatarFileExtension(String mime, {String fileName = ''}) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0 && dot < fileName.length - 1 && fileName.length - dot <= 8) {
    return fileName.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
  }
  return switch (mime.toLowerCase()) {
    'video/mp4' => '.mp4',
    'video/webm' => '.webm',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'image/png' => '.png',
    _ => '.jpg',
  };
}

String guessAvatarMimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return '';
}

/// Extensions the client can name without inspecting the bytes.
///
/// The server falls back to sniffing the first 512 bytes when no MIME is
/// supplied, which cannot tell an m4a voice memo from an mp4 video: both start
/// with an `ftyp` box and end up as video/mp4. Sending the real type avoids
/// that mislabel for every format the picker and recorder can produce.
const _uploadMimes = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  '3gp': 'video/3gpp',
  'avi': 'video/x-msvideo',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/ogg',
  'flac': 'audio/flac',
  'amr': 'audio/amr',
};

/// The MIME to declare for [path], or an empty string when the extension is
/// unknown and the server should sniff instead.
String uploadMimeForPath(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return '';
  final mime = _uploadMimes[name.substring(dot + 1).toLowerCase()];
  return mime ?? '';
}
