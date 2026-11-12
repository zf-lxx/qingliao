part of 'ql_engine.dart';

int qlDeviceInt(String id) {
  final v = _fnv1a64('dv:$id') & 0x7FFFFFFFFFFFFFFF;
  return v == 0 ? 1 : v;
}

int qlAlbumInt(String id) {
  final v = _fnv1a64('sa:$id') & 0x7FFFFFFFFFFFFFFF;
  return v == 0 ? 1 : v;
}

extension _QlAccount on QlTdEngine {
  QlProxyConfig? get _activeProxy {
    for (final p in _proxies) {
      if (p.enabled) return p;
    }
    return null;
  }

  void _applyProxyToApi() {
    _api?.applyProxy(_activeProxy);
  }

  void _loadProxies() {
    _proxies.clear();
    try {
      final file = File(_proxyPath);
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return;
      final list = raw['proxies'];
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final proxy = QlProxyConfig.fromJson(Map<String, dynamic>.from(item));
        if (proxy.id > _proxySeq) _proxySeq = proxy.id;
        if (proxy.host.isNotEmpty && (proxy.isHttp || proxy.isSocks)) {
          _proxies.add(proxy);
        }
      }
    } catch (_) {}
    _applyProxyToApi();
  }

  void _saveProxies() {
    if (_databaseDir.isEmpty) return;
    final file = File(_proxyPath);
    file.writeAsStringSync(
      jsonEncode({
        'proxies': [for (final p in _proxies) p.toJson()],
      }),
      flush: true,
    );
  }

  Map<String, dynamic> _getProxies() {
    _loadProxies();
    return {
      '@type': 'proxies',
      'proxies': [for (final p in _proxies) p.toTd()],
    };
  }

  Future<Map<String, dynamic>> _addProxy(Map<String, dynamic> r) async {
    final built = _proxyFromRequest(r, id: 0);
    if (built == null) return _error(400, '目前仅支持 HTTP 和 SOCKS5 代理');
    final enabled = r['enable'] == true;
    final proxy = built.copyWith(
      id: ++_proxySeq,
      enabled: enabled,
      lastUsedDate: enabled ? _nowSeconds() : 0,
    );
    if (enabled) {
      _proxies = [
        for (final p in _proxies) p.copyWith(enabled: false),
        proxy,
      ];
    } else {
      _proxies.add(proxy);
    }
    _saveProxies();
    _applyProxyToApi();
    return proxy.toTd();
  }

  Future<Map<String, dynamic>> _editProxy(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['proxy_id']) ?? 0;
    final index = _proxies.indexWhere((p) => p.id == id);
    if (index < 0) return _error(400, '找不到这个代理');
    final built = _proxyFromRequest(r, id: id);
    if (built == null) return _error(400, '目前仅支持 HTTP 和 SOCKS5 代理');
    final prev = _proxies[index];
    _proxies[index] = built.copyWith(enabled: prev.enabled, lastUsedDate: prev.lastUsedDate);
    _saveProxies();
    _applyProxyToApi();
    return _proxies[index].toTd();
  }

  Future<Map<String, dynamic>> _removeProxy(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['proxy_id']) ?? 0;
    _proxies.removeWhere((p) => p.id == id);
    _saveProxies();
    _applyProxyToApi();
    return _ok;
  }

  Future<Map<String, dynamic>> _enableProxy(
    Map<String, dynamic> r, {
    required bool enabled,
  }) async {
    final id = QlTdEngine._int(r['proxy_id']) ?? 0;
    _proxies = [
      for (final p in _proxies)
        p.copyWith(
          enabled: enabled && p.id == id,
          lastUsedDate: enabled && p.id == id ? _nowSeconds() : p.lastUsedDate,
        ),
    ];
    _saveProxies();
    _applyProxyToApi();
    return _ok;
  }

  Future<Map<String, dynamic>> _pingProxy(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['proxy_id']) ?? 0;
    QlProxyConfig? proxy;
    for (final p in _proxies) {
      if (p.id == id) proxy = p;
    }
    if (proxy == null) return _error(400, '找不到这个代理');
    final sw = Stopwatch()..start();
    try {
      if (proxy.isSocks) {
        final socket = await qlSocks5Connect(
          proxyHost: proxy.host,
          proxyPort: proxy.port,
          destHost: qlDefaultServer.replaceFirst('https://', '').replaceFirst('http://', ''),
          destPort: 443,
          username: proxy.username,
          password: proxy.password,
        );
        socket.destroy();
      } else {
        final client = HttpClient();
        qlApplyProxy(client, proxy);
        try {
          final req = await client.getUrl(Uri.parse(qlDefaultServer));
          await req.close().timeout(const Duration(seconds: 8));
        } finally {
          client.close(force: true);
        }
      }
      return {'@type': 'seconds', 'seconds': sw.elapsedMilliseconds / 1000.0};
    } catch (e) {
      return _error(400, '无法通过该代理连接');
    }
  }

  QlProxyConfig? _proxyFromRequest(Map<String, dynamic> r, {required int id}) {
    final type = r['type'];
    if (type is! Map) return null;
    final typ = type['@type']?.toString() ?? '';
    if (typ == 'proxyTypeMtproto' || typ == 'proxyTypeWeb') return null;
    final kind = typ == 'proxyTypeHttp' ? 'http' : (typ == 'proxyTypeSocks5' ? 'socks5' : '');
    if (kind.isEmpty) return null;
    final host = r['server']?.toString() ?? '';
    final port = QlTdEngine._int(r['port']) ?? 0;
    if (host.isEmpty || port <= 0 || port > 65535) return null;
    return QlProxyConfig(
      id: id,
      host: host,
      port: port,
      type: kind,
      username: type['username']?.toString() ?? '',
      password: type['password']?.toString() ?? '',
    );
  }

  Future<Map<String, dynamic>> _loginTotp(Map<String, dynamic> r) async {
    if (_databaseDir.isEmpty) return _error(400, 'Client is not initialized');
    final server = qlNormalizeServer(r['server']?.toString() ?? '');
    final handle = (r['handle']?.toString() ?? '').trim().toLowerCase();
    final token = r['pending_token']?.toString() ?? '';
    final code = r['totp_code']?.toString() ?? '';
    final recovery = r['recovery_code']?.toString() ?? '';
    if (token.isEmpty || (code.isEmpty && recovery.isEmpty)) {
      return _error(400, '请输入两步验证码');
    }
    final api = QlApi(server, proxy: _activeProxy);
    try {
      final result = await api.post('/auth/login/totp', {
        'pending_token': token,
        if (code.isNotEmpty) 'totp_code': code,
        if (recovery.isNotEmpty) 'recovery_code': recovery,
        'platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
        'app_name': '轻聊',
        'app_version': '0.4.2',
        'device_model': Platform.operatingSystem,
      });
      final access = result['access_token']?.toString() ?? '';
      final userId = result['user_id']?.toString() ?? '';
      if (access.isEmpty || userId.isEmpty) {
        return _error(500, '服务器返回异常');
      }
      final session = QlSession(
        server: server.toString(),
        token: access,
        userId: userId,
        deviceId: result['device_id']?.toString() ?? '',
        handle: handle,
      );
      _writeSession(session);
      _startSession(session);
      return _ok;
    } finally {
      api.close();
    }
  }

  Future<Map<String, dynamic>> _getPasswordState() async {
    final sec = await _apiOrThrow.get('/me/security');
    return {
      '@type': 'passwordState',
      'has_password': true,
      'password_hint': sec['password_hint']?.toString() ?? '',
      'has_recovery_email_address': false,
      'has_passport_data': false,
      'recovery_email_address_code_info': null,
      'login_email_address_pattern': '',
      'pending_reset_date': 0,
      '@ql_two_factor_enabled': sec['two_factor_enabled'] == true,
      '@ql_two_factor_pending': sec['two_factor_pending'] == true,
    };
  }

  Future<Map<String, dynamic>> _setPassword(Map<String, dynamic> r) async {
    final next = r['new_password']?.toString() ?? '';
    if (next.isEmpty) {
      return _error(400, '登录密码不能关闭，只能修改');
    }
    if (next.length < 12) {
      return _error(400, '新密码至少 12 个字符');
    }
    if (r['set_recovery_email_address'] == true &&
        (r['new_recovery_email_address']?.toString() ?? '').isNotEmpty) {
      return _error(400, '恢复邮箱暂未开放');
    }
    await _apiOrThrow.post('/me/password', {
      'old_password': r['old_password']?.toString() ?? '',
      'new_password': next,
      'hint': r['new_hint']?.toString() ?? '',
    });
    return _getPasswordState();
  }

  Future<Map<String, dynamic>> _startTotp() async {
    final raw = await _apiOrThrow.post('/me/totp/start');
    return {
      '@type': 'qlTotpStart',
      'secret': raw['secret']?.toString() ?? '',
      'otpauth_url': raw['otpauth_url']?.toString() ?? '',
    };
  }

  Future<Map<String, dynamic>> _confirmTotp(Map<String, dynamic> r) async {
    final raw = await _apiOrThrow.post('/me/totp/confirm', {
      'code': r['code']?.toString() ?? '',
    });
    return {
      '@type': 'qlTotpConfirmed',
      'recovery_codes': raw['recovery_codes'] ?? const <Object>[],
    };
  }

  Future<Map<String, dynamic>> _disableTotp(Map<String, dynamic> r) async {
    await _apiOrThrow.post('/me/totp/disable', {
      'password': r['password']?.toString() ?? '',
      'code': r['code']?.toString() ?? r['totp_code']?.toString() ?? '',
      if ((r['recovery_code']?.toString() ?? '').isNotEmpty)
        'recovery_code': r['recovery_code'].toString(),
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _deleteAccount(Map<String, dynamic> r) async {
    await _apiOrThrow.post('/me/delete', {
      'password': r['password']?.toString() ?? '',
      'reason': r['reason']?.toString() ?? '',
      if ((r['totp_code']?.toString() ?? '').isNotEmpty)
        'totp_code': r['totp_code'].toString(),
      if ((r['recovery_code']?.toString() ?? '').isNotEmpty)
        'recovery_code': r['recovery_code'].toString(),
    });
    return _logOut();
  }

  Future<Map<String, dynamic>> _getActiveSessions() async {
    final raw = await _apiOrThrow.get('/devices');
    final list = raw['devices'] is List ? raw['devices'] as List : const [];
    final sessions = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final d = Map<String, dynamic>.from(item);
      final id = d['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final iid = qlDeviceInt(id);
      _deviceByInt[iid] = id;
      sessions.add({
        '@type': 'session',
        'id': iid,
        'is_current': d['current'] == true,
        'is_password_pending': false,
        'can_accept_secret_chats': false,
        'can_accept_calls': false,
        'type': {'@type': _sessionType(d['platform']?.toString() ?? '')},
        'api_id': 0,
        'application_name': (d['app_name']?.toString().isNotEmpty ?? false)
            ? d['app_name']
            : '轻聊',
        'application_version': d['app_version'] ?? '',
        'is_official_application': true,
        'device_model': d['device_model'] ?? d['platform'] ?? '',
        'platform': d['platform'] ?? '',
        'system_version': '',
        'log_in_date': _parseDate(d['created_at']),
        'last_active_date': _parseDate(d['last_seen']),
        'ip_address': d['last_ip'] ?? '',
        'location': '',
        'country': '',
        'region': '',
      });
    }
    return {
      '@type': 'sessions',
      'sessions': sessions,
      'inactive_session_ttl_days': 180,
    };
  }

  String _sessionType(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android')) return 'sessionTypeAndroid';
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return 'sessionTypeApple';
    }
    if (p.contains('mac')) return 'sessionTypeMac';
    if (p.contains('win')) return 'sessionTypeWindows';
    if (p.contains('linux')) return 'sessionTypeLinux';
    return 'sessionTypeUnknown';
  }

  Future<Map<String, dynamic>> _terminateSession(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['session_id']) ?? 0;
    final backend = _deviceByInt[id];
    if (backend == null || backend.isEmpty) return _error(400, '找不到这个登录设备');
    await _apiOrThrow.delete('/devices/$backend');
    return _ok;
  }

  Future<Map<String, dynamic>> _terminateOtherSessions() async {
    await _apiOrThrow.post('/devices/revoke-others');
    return _ok;
  }

  String? _stickerLocalPath(Map sticker) {
    final input = sticker['sticker'];
    if (input is Map) {
      final typ = input['@type']?.toString() ?? '';
      if (typ == 'inputFileLocal') return input['path']?.toString();
      if (typ == 'inputFileId') {
        final fid = QlTdEngine._int(input['id']) ?? 0;
        final f = _files[fid];
        if (f != null && f.localPath.isNotEmpty) return f.localPath;
      }
    }
    return null;
  }

  String _stickerEmoji(Map sticker) {
    final raw = sticker['emojis'];
    if (raw is List && raw.isNotEmpty) return raw.first.toString();
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? '⭐' : text;
  }

  bool _stickerFormatAllowed(Map sticker) {
    final format = (sticker['format'] as Map?)?['@type']?.toString() ?? '';
    return format.isEmpty ||
        format == 'stickerFormatWebp' ||
        format == 'stickerFormatPng';
  }

  Future<Map<String, dynamic>> _createNewStickerSet(Map<String, dynamic> r) async {
    final typ = (r['sticker_type'] as Map?)?['@type']?.toString() ?? 'stickerTypeRegular';
    if (typ != 'stickerTypeRegular') {
      return _error(400, '目前仅支持普通 PNG 表情包');
    }
    final title = (r['title']?.toString() ?? '').trim();
    if (title.isEmpty) return _error(400, '请填写表情包名称');
    final stickers = r['stickers'] is List ? r['stickers'] as List : const [];
    if (stickers.isEmpty) return _error(400, '请至少添加一张贴纸');
    for (final raw in stickers) {
      if (raw is! Map || !_stickerFormatAllowed(raw)) {
        return _error(400, '目前仅支持 PNG / WebP 贴纸，不支持动画格式');
      }
    }
    final created = await _apiOrThrow.post('/sticker-packs', {'title': title, 'is_emoji': false});
    final packId = created['id']?.toString() ?? '';
    if (packId.isEmpty) return _error(500, '创建表情包失败');
    for (final raw in stickers) {
      final err = await _uploadAndAddSticker(packId, Map<String, dynamic>.from(raw as Map));
      if (err != null) return err;
    }
    return _getStickerSet({'set_id': qlPackInt(packId)});
  }

  Future<Map<String, dynamic>> _addStickerToSet(Map<String, dynamic> r) async {
    final name = r['name']?.toString() ?? '';
    final sticker = r['sticker'];
    if (name.isEmpty || sticker is! Map) return _error(400, '贴纸参数无效');
    if (!_stickerFormatAllowed(sticker)) {
      return _error(400, '目前仅支持 PNG / WebP 贴纸，不支持动画格式');
    }
    final packId = await _packIdByName(name);
    if (packId == null) return _error(404, '找不到这个表情包');
    final err = await _uploadAndAddSticker(packId, Map<String, dynamic>.from(sticker));
    if (err != null) return err;
    return _getStickerSet({'set_id': qlPackInt(packId)});
  }

  Future<String?> _packIdByName(String name) async {
    if (name.isEmpty) return null;
    final want = int.tryParse(name);
    final raw = await _apiOrThrow.get('/sticker-packs');
    for (final item in (raw['packs'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id == name) return id;
      if (want != null && qlPackInt(id) == want) return id;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _uploadAndAddSticker(
    String packId,
    Map<String, dynamic> sticker,
  ) async {
    final path = _stickerLocalPath(sticker);
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return _error(400, '找不到贴纸文件');
    }
    final uploaded = await _apiOrThrow.uploadFile(path);
    final mediaId = uploaded['id']?.toString() ?? '';
    if (mediaId.isEmpty) return _error(500, '贴纸上传失败');
    await _apiOrThrow.post('/sticker-packs/$packId/stickers', {
      'emoji': _stickerEmoji(sticker),
      'media_id': mediaId,
    });
    return null;
  }

  String? _albumIdFromInt(int id) => _albumByInt[id];

  int _rememberAlbum(String id) {
    final iid = qlAlbumInt(id);
    _albumByInt[iid] = id;
    return iid;
  }

  Map<String, dynamic> _tdStoryAlbum(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final nos = raw['story_nos'] is List ? raw['story_nos'] as List : const [];
    return {
      '@type': 'storyAlbum',
      'id': _rememberAlbum(id),
      'name': raw['title'] ?? raw['name'] ?? '',
      'photo': null,
      'count': nos.length,
    };
  }

  Future<Map<String, dynamic>> _getChatStoryAlbums(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['chat_id']) ?? 0) ?? _myId;
    final raw = await _apiOrThrow.get('/story-albums', {'owner': author});
    final albums = <Map<String, dynamic>>[
      for (final item in (raw['albums'] as List? ?? const []))
        if (item is Map) _tdStoryAlbum(Map<String, dynamic>.from(item)),
    ];
    return {'@type': 'storyAlbums', 'albums': albums};
  }

  Future<Map<String, dynamic>> _createStoryAlbum(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id'] ?? r['chat_id']) ?? 0);
    if (author != null && author != _myId) return _error(403, '只能为自己的动态创建专辑');
    final title = (r['name']?.toString() ?? '').trim();
    if (title.isEmpty) return _error(400, '请填写专辑名称');
    final nos = [
      for (final v in (r['story_ids'] as List? ?? const []))
        if (QlTdEngine._int(v) != null && QlTdEngine._int(v)! > 0) QlTdEngine._int(v)!,
    ];
    final raw = await _apiOrThrow.post('/story-albums', {
      'title': title,
      'story_nos': nos,
    });
    return _tdStoryAlbum(Map<String, dynamic>.from(raw));
  }

  Future<Map<String, dynamic>> _getStoryAlbumStories(Map<String, dynamic> r) async {
    final id = _albumIdFromInt(QlTdEngine._int(r['story_album_id']) ?? 0);
    if (id == null) return _error(404, '找不到这个专辑');
    final offset = QlTdEngine._int(r['offset']) ?? 0;
    final limit = QlTdEngine._int(r['limit']) ?? 100;
    final raw = await _apiOrThrow.get('/story-albums/$id', {
      'offset': '$offset',
      'limit': '$limit',
    });
    final author = raw['owner']?.toString() ?? _myId;
    final stories = <Map<String, dynamic>>[
      for (final item in (raw['stories'] as List? ?? const []))
        if (item is Map) _tdStory(Map<String, dynamic>.from(item), viewer: _myId),
    ];
    if (stories.isEmpty) {
      // Fall back to wrapping story numbers if the payload only has nos.
      for (final no in (raw['story_nos'] as List? ?? const [])) {
        final n = QlTdEngine._int(no) ?? 0;
        if (n <= 0) continue;
        try {
          final one = await _apiOrThrow.get('/users/$author/stories/$n');
          stories.add(_tdStory(one, viewer: _myId));
        } catch (_) {}
      }
    }
    return {
      '@type': 'stories',
      'total_count': QlTdEngine._int(raw['total']) ?? stories.length,
      'stories': stories,
    };
  }

  Future<Map<String, dynamic>> _setStoryAlbumName(Map<String, dynamic> r) async {
    final id = _albumIdFromInt(QlTdEngine._int(r['story_album_id']) ?? 0);
    if (id == null) return _error(404, '找不到这个专辑');
    final raw = await _apiOrThrow.patch('/story-albums/$id', {
      'title': (r['name']?.toString() ?? '').trim(),
    });
    raw['id'] = id;
    return {
      '@type': 'storyAlbum',
      'id': qlAlbumInt(id),
      'name': raw['title'] ?? r['name'] ?? '',
      'photo': null,
      'count': 0,
    };
  }

  Future<Map<String, dynamic>> _reorderStoryAlbums(Map<String, dynamic> r) async {
    final ids = <String>[];
    for (final v in (r['story_album_ids'] as List? ?? const [])) {
      final id = _albumIdFromInt(QlTdEngine._int(v) ?? 0);
      if (id != null) ids.add(id);
    }
    await _apiOrThrow.post('/story-albums/reorder', {'album_ids': ids});
    return _ok;
  }

  Future<Map<String, dynamic>> _deleteStoryAlbum(Map<String, dynamic> r) async {
    final id = _albumIdFromInt(QlTdEngine._int(r['story_album_id']) ?? 0);
    if (id == null) return _error(404, '找不到这个专辑');
    await _apiOrThrow.delete('/story-albums/$id');
    return _ok;
  }

  Future<Map<String, dynamic>> _mutateStoryAlbumStories(
    Map<String, dynamic> r,
    String op,
  ) async {
    final id = _albumIdFromInt(QlTdEngine._int(r['story_album_id']) ?? 0);
    if (id == null) return _error(404, '找不到这个专辑');
    final nos = [
      for (final v in (r['story_ids'] as List? ?? const []))
        if (QlTdEngine._int(v) != null && QlTdEngine._int(v)! > 0) QlTdEngine._int(v)!,
    ];
    await _apiOrThrow.put('/story-albums/$id/stories', {
      'op': op,
      'story_nos': nos,
    });
    return _ok;
  }
}
