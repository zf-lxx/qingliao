part of 'ql_engine.dart';

class _QlFile {
  _QlFile(this.id);

  final int id;
  String mediaId = '';
  String localPath = '';
  String kind = 'file';
  String fileName = '';
  String stickerId = '';
  String stickerFileId = '';
  int size = 0;
  int downloaded = 0;
  bool downloading = false;
  bool uploading = false;
  int uploaded = 0;
  Future<void>? download;
}

extension on QlTdEngine {
  String _extFor(String kind, String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1 && fileName.length - dot <= 8) {
      return fileName.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    }
    return switch (kind) {
      'image' || 'avatar' => '.jpg',
      'voice' => '.ogg',
      'video' => '.mp4',
      _ => '',
    };
  }

  String _mediaPath(String mediaId, String kind, String fileName) =>
      '$_filesDir/qingliao/$mediaId${_extFor(kind, fileName)}';

  Map<String, dynamic> _fileForMedia(
    String mediaId, {
    required String kind,
    int size = 0,
    String fileName = '',
  }) {
    if (mediaId.isEmpty) return _tdFile(_QlFile(0));
    final id = qlMediaFileId(mediaId);
    final f = _files.putIfAbsent(id, () => _QlFile(id));
    f.mediaId = mediaId;
    if (f.kind == 'file' || kind != 'file') f.kind = kind;
    if (fileName.isNotEmpty) f.fileName = fileName;
    if (size > 0) f.size = size;
    if (f.localPath.isEmpty && _filesDir.isNotEmpty) {
      final path = _mediaPath(mediaId, f.kind, f.fileName);
      final file = File(path);
      if (file.existsSync()) {
        f.localPath = path;
        f.size = file.lengthSync();
        f.downloaded = f.size;
      }
    }
    return _tdFile(f);
  }

  _QlFile _localFile(String path) {
    final id = (_fnv1a64('l:$path:${DateTime.now().microsecondsSinceEpoch}') & 0x3FFFFFFF) | 0x40000000;
    final f = _files.putIfAbsent(id, () => _QlFile(id));
    f.localPath = path;
    try {
      f.size = File(path).lengthSync();
    } catch (_) {}
    f.downloaded = f.size;
    return f;
  }

  Map<String, dynamic> _tdFile(_QlFile f) {
    final complete = f.localPath.isNotEmpty && !f.downloading;
    return {
      '@type': 'file',
      'id': f.id,
      'size': f.size,
      'expected_size': f.size,
      'local': {
        '@type': 'localFile',
        'path': complete ? f.localPath : '',
        'can_be_downloaded': f.mediaId.isNotEmpty || f.stickerFileId.isNotEmpty,
        'can_be_deleted': complete && f.mediaId.isNotEmpty,
        'is_downloading_active': f.downloading,
        'is_downloading_completed': complete,
        'download_offset': 0,
        'downloaded_prefix_size': complete ? f.size : f.downloaded,
        'downloaded_size': complete ? f.size : f.downloaded,
      },
      'remote': {
        '@type': 'remoteFile',
        'id': f.stickerId.isNotEmpty ? f.stickerId : f.mediaId,
        'unique_id': f.stickerId.isNotEmpty ? f.stickerId : f.mediaId,
        'is_uploading_active': f.uploading,
        'is_uploading_completed': f.mediaId.isNotEmpty && !f.uploading,
        'uploaded_size': f.mediaId.isNotEmpty ? f.size : f.uploaded,
      },
    };
  }

  void _emitFile(_QlFile f) => _emit({'@type': 'updateFile', 'file': _tdFile(f)});

  Map<String, dynamic> _getFile(int id) {
    final f = _files[id];
    if (f == null) return _error(404, 'File not found');
    return _tdFile(f);
  }

  Map<String, dynamic> _getRemoteFile(String remoteId) {
    if (remoteId.isEmpty) return _error(400, 'remote_file_id required');
    for (final f in _files.values) {
      if (f.stickerId == remoteId || f.mediaId == remoteId) return _tdFile(f);
    }
    if (remoteId.startsWith('st-') || !remoteId.contains('-') && remoteId.length < 16) {
      return _fileForSticker(stickerId: remoteId, fileId: remoteId);
    }
    return _fileForMedia(remoteId, kind: 'file');
  }

  Future<Map<String, dynamic>> _downloadFile(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['file_id']) ?? 0;
    final f = _files[id];
    if (f == null) return _error(404, 'File not found');
    if (f.localPath.isNotEmpty && !f.downloading) return _tdFile(f);
    if (f.mediaId.isEmpty && f.stickerFileId.isEmpty) return _error(400, 'File can not be downloaded');
    f.download ??= _runDownload(f);
    if (r['synchronous'] == true) {
      await f.download;
      if (f.localPath.isEmpty) return _error(500, 'DOWNLOAD_FAILED');
    }
    return _tdFile(f);
  }

  Future<void> _runDownload(_QlFile f) async {
    final api = _api;
    if (api == null) {
      f.download = null;
      return;
    }
    f.downloading = true;
    _emitFile(f);
    final path = f.mediaId.isNotEmpty
        ? _mediaPath(f.mediaId, f.kind, f.fileName)
        : '$_filesDir/qingliao/stickers/${f.stickerFileId}.png';
    var lastEmit = DateTime.now();
    try {
      final bytes = await api.downloadPath(
        f.mediaId.isNotEmpty ? '/media/${f.mediaId}' : '/sticker-files/${f.stickerFileId}',
        path,
        onProgress: (received, total) {
          f.downloaded = received;
          if (total > 0) f.size = total;
          final now = DateTime.now();
          if (now.difference(lastEmit).inMilliseconds > 150) {
            lastEmit = now;
            _emitFile(f);
          }
        },
      );
      f.size = bytes;
      f.downloaded = bytes;
      f.localPath = path;
      f.downloading = false;
      _emitFile(f);
      if (f.kind == 'image') _learnImageDims(f.mediaId, path);
    } catch (_) {
      f.downloading = false;
      f.downloaded = 0;
      _emitFile(f);
    } finally {
      f.download = null;
    }
  }

  /// The backend stores no image dimensions yet; learn them from the file
  /// header once downloaded and refresh any message that showed 0x0.
  void _learnImageDims(String mediaId, String path) {
    if (_mediaDims.containsKey(mediaId)) return;
    final size = qlImageSizeOfFile(path);
    if (size == null) return;
    _mediaDims[mediaId] = [size.$1, size.$2];
    _schedulePersist();
    for (final c in _convs.values) {
      for (final entry in c.messages.entries) {
        final content = entry.value['content'];
        if (content is! Map || content['@type'] != 'messagePhoto') continue;
        final sizes = (content['photo'] as Map)['sizes'] as List;
        final photo = sizes.first as Map;
        final file = photo['photo'] as Map;
        if ((file['remote'] as Map)['id'] != mediaId) continue;
        photo['width'] = size.$1;
        photo['height'] = size.$2;
        _emit({
          '@type': 'updateMessageContent',
          'chat_id': c.chatId,
          'message_id': entry.value['id'],
          'new_content': content,
        });
      }
    }
  }

  Map<String, dynamic> _deleteLocalFile(int id) {
    final f = _files[id];
    if (f == null) return _error(404, 'File not found');
    if (f.localPath.isNotEmpty && f.mediaId.isNotEmpty) {
      try {
        File(f.localPath).deleteSync();
      } catch (_) {}
      f.localPath = '';
      f.downloaded = 0;
      _emitFile(f);
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _readFilePart(Map<String, dynamic> r) async {
    final f = _files[QlTdEngine._int(r['file_id']) ?? 0];
    if (f == null || f.localPath.isEmpty) return _error(404, 'File not found');
    final offset = QlTdEngine._int(r['offset']) ?? 0;
    var count = QlTdEngine._int(r['count']) ?? 0;
    final raf = await File(f.localPath).open();
    try {
      final length = await raf.length();
      if (count <= 0 || offset + count > length) count = length - offset;
      await raf.setPosition(offset);
      final bytes = await raf.read(count);
      return {'@type': 'data', 'data': base64Encode(bytes)};
    } finally {
      await raf.close();
    }
  }
}
