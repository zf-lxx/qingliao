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
