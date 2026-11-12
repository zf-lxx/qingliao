Map<String, dynamic>? animatedProfilePhotoRequest({
  bool isPremium = true,
  required String path,
}) {
  // isPremium is ignored: 轻聊 has no membership gate for animated avatars.
  if (path.isEmpty) return null;
  return {
    '@type': 'setProfilePhoto',
    'photo': {
      '@type': 'inputChatPhotoAnimation',
      'animation': {'@type': 'inputFileLocal', 'path': path},
      'main_frame_timestamp': 0.0,
    },
    'is_public': false,
  };
}
