part of 'ql_engine.dart';

extension on QlTdEngine {
  // MARK: Chat list

  String _listKey(Object? list) {
    if (list is Map && list['@type'] == 'chatListArchive') return 'archive';
    if (list is Map && list['@type'] == 'chatListFolder') {
      return 'folder:${list['chat_folder_id'] ?? 0}';
    }
    return 'main';
  }

  bool _folderMatchesKey(_Conv c, String key) {
    final id = int.tryParse(key.substring('folder:'.length)) ?? 0;
    final fid = _folderIdByInt[id];
    final folder = fid == null ? null : _folders[fid];
    if (folder == null) return false;
    return _convMatchesFolder(c, folder);
  }

  bool _isSelfConv(_Conv c) =>
      !c.isGroup && (c.peerId == _myId || (_myInt != 0 && c.chatId == _myInt));

  List<_Conv> _sortedConvs(Object? list) {
    final key = _listKey(list);
    final out = [
      for (final c in _convs.values)
        if (c.announced && !c.id.startsWith('virtual:') && !_isSelfConv(c) &&
            (key == 'archive'
                ? c.archived
                : (key == 'main'
                    ? !c.archived
                    : (key.startsWith('folder:') && _folderMatchesKey(c, key)))))
          c,
    ]..sort((a, b) => _chatOrder(b).compareTo(_chatOrder(a)));
    return out;
  }

  Future<Map<String, dynamic>> _loadChats(Map<String, dynamic> r) async {
    if (_session == null) return _error(401, 'Unauthorized');
    if (!_hasServableLocalChats) await _waitInitialLoad();
    final key = _listKey(r['chat_list']);
    if (key.startsWith('folder:') && !_folders.values.any((f) => 'folder:${qlFolderInt(f['id']?.toString() ?? '')}' == key) && _folderIdByInt[int.tryParse(key.substring(7)) ?? 0] == null) {
      return _error(404, 'Not Found');
    }
    final served = _servedLists.putIfAbsent(key, () => <String>{});
    final pending = [
      for (final c in _sortedConvs(r['chat_list']))
        if (!served.contains(c.id)) c,
    ];
    if (pending.isEmpty) return _error(404, 'Not Found');
    final limit = math.max(1, QlTdEngine._int(r['limit']) ?? 100);
    for (final c in pending.take(limit)) {
      served.add(c.id);
      _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c)});
    }
    return _ok;
  }

  _Conv? _conv(int chatId) => _convByChatId[chatId];

  Future<Map<String, dynamic>> _getChat(int chatId) async {
    var c = _conv(chatId);
    if (c == null) {
      await _waitInitialLoad();
      c = _conv(chatId);
    }
    if (c == null) return _error(400, 'Chat not found');
    return _tdChat(c);
  }

  Future<Map<String, dynamic>> _createPrivateChat(int userInt) async {
    await _waitInitialLoad();
    final existing = _conv(userInt);
    if (existing != null) return _tdChat(existing);
    final uid = _userIdByInt[userInt];
    if (uid == null) return _error(400, 'User not found');
    await _ensureUser(uid);
    final c = _Conv('virtual:$uid')
      ..kind = 'direct'
      ..peerId = uid
      ..membersLoaded = true;
    _convs[c.id] = c;
    _assignChatId(c);
    if (uid != _myId) _announce(c);
    return _tdChat(c);
  }

  /// Turns a "virtual" (search result) private chat into a real backend
  /// conversation on first send.
  Future<_Conv> _materialize(_Conv c) async {
    if (!c.id.startsWith('virtual:')) return c;
    final result = await _apiOrThrow.post('/conversations', {
      'kind': 'direct',
      'member_ids': [c.peerId],
    });
    final id = result['id']?.toString() ?? '';
    if (id.isEmpty) throw const QlApiException(500, 'create_failed');
    final existing = _convs[id];
    if (existing != null) return existing;
    _convs.remove(c.id);
    final real = _Conv(id)
      ..kind = 'direct'
      ..peerId = c.peerId
      ..membersLoaded = true
      ..announced = c.announced
      ..lastActivityMicros = DateTime.now().microsecondsSinceEpoch;
    _convs[id] = real;
    _assignChatId(real);
    _emit({'@type': 'updateChatPosition', 'chat_id': real.chatId, 'position': _position(real)});
    return real;
  }

  Future<Map<String, dynamic>> _createGroup(Map<String, dynamic> r) async {
    final title = (r['title']?.toString() ?? '').trim();
    final ids = [
      for (final v in (r['user_ids'] as List? ?? const []))
        if (_userIdByInt[QlTdEngine._int(v) ?? 0] case final uid?) uid,
    ];
    if (title.isEmpty) return _error(400, '请输入群名称');
    final result = await _apiOrThrow.post('/conversations', {
      'kind': 'group',
      'title': title,
      'member_ids': ids,
    });
    final id = result['id']?.toString() ?? '';
    final c = await _discoverConversation(id);
    if (c == null) return _error(500, 'Group was created but could not be loaded');
    return {
      '@type': 'createdBasicGroupChat',
      'chat_id': c.chatId,
      'failed_to_add_members': {'@type': 'failedToAddMembers', 'failed_to_add_members': const <Object>[]},
    };
  }

  Map<String, dynamic> _searchChats(Map<String, dynamic> r) {
    final q = (r['query']?.toString() ?? '').trim().toLowerCase();
    final limit = QlTdEngine._int(r['limit']) ?? 50;
    final ids = <int>[];
    for (final c in _sortedConvs({'@type': 'chatListMain'}) + _sortedConvs({'@type': 'chatListArchive'})) {
      final handle = c.peerId == null ? '' : (_users[c.peerId!]?['handle']?.toString() ?? '');
      if (q.isEmpty || _chatTitle(c).toLowerCase().contains(q) || handle.contains(q)) {
        ids.add(c.chatId);
      }
      if (ids.length >= limit) break;
    }
    return {'@type': 'chats', 'total_count': ids.length, 'chat_ids': ids};
  }

  Future<Map<String, dynamic>> _searchUsers(Map<String, dynamic> r, {required bool chats}) async {
    final q = (r['query']?.toString() ?? '').trim().replaceFirst('@', '').toLowerCase();
    if (q.length < 2) {
      if (chats) return {'@type': 'chats', 'total_count': 0, 'chat_ids': const <int>[]};
      final contacts = <int>{
        for (final c in _convs.values)
          if (!c.isGroup && c.peerId != null && !c.id.startsWith('virtual:')) qlUserInt(c.peerId!),
      };
      return {'@type': 'users', 'total_count': contacts.length, 'user_ids': contacts.toList()};
    }
    final result = await _apiOrThrow.get('/users', {'q': q.length > 32 ? q.substring(0, 32) : q});
    final users = <String>[];
    final list = result['users'];
    if (list is List) {
      for (final u in list) {
        if (u is! Map) continue;
        final raw = Map<String, dynamic>.from(u);
        _rememberUser(raw);
        final id = raw['id']?.toString() ?? '';
        if (id.isNotEmpty && id != _myId) users.add(id);
      }
    }
    if (!chats) {
      return {
        '@type': 'users',
        'total_count': users.length,
        'user_ids': [for (final u in users) qlUserInt(u)],
      };
    }
    final chatIds = <int>[];
    for (final u in users) {
      final chat = await _createPrivateChat(qlUserInt(u));
      final id = QlTdEngine._int(chat['id']);
      if (id != null) chatIds.add(id);
    }
    return {'@type': 'chats', 'total_count': chatIds.length, 'chat_ids': chatIds};
  }

  Future<Map<String, dynamic>> _searchPublicChat(String username) async {
    final handle = username.trim().replaceFirst('@', '').toLowerCase();
    if (handle.length < 2) return _error(400, 'USERNAME_INVALID');
    final result = await _apiOrThrow.get('/users', {'q': handle});
    final list = result['users'];
    if (list is List) {
      for (final u in list) {
        if (u is Map && u['handle']?.toString() == handle) {
          final raw = Map<String, dynamic>.from(u);
          _rememberUser(raw);
          if (raw['id']?.toString() == _myId) {
            return _error(400, 'USERNAME_NOT_OCCUPIED');
          }
          return _createPrivateChat(qlUserInt(raw['id'].toString()));
        }
      }
    }
    return _error(400, 'USERNAME_NOT_OCCUPIED');
  }

  // MARK: Per-chat state

  Future<Map<String, dynamic>> _patchState(_Conv c, Map<String, dynamic> body) async {
    if (c.id.startsWith('virtual:')) return _error(400, 'Chat has no messages yet');
    await _apiOrThrow.patch('/conversations/${c.id}/state', body);
    return _ok;
  }

  Future<Map<String, dynamic>> _togglePinned(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final pin = r['is_pinned'] == true;
    var order = 0;
    if (pin) {
      order = 1;
      for (final x in _convs.values) {
        if (x.pinnedOrder >= order) order = x.pinnedOrder + 1;
      }
      order = math.min(order, 1000);
    }
    final result = await _patchState(c, {'pinned_order': order});
    if (result['@type'] == 'ok') {
      _applyDialog({'id': c.id, 'pinned_order': order}, emitChanges: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> _markUnread(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final unread = r['is_marked_as_unread'] == true;
    final result = await _patchState(c, {'mark_unread': unread});
    if (result['@type'] == 'ok') {
      _applyDialog({'id': c.id, 'manual_unread': unread}, emitChanges: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> _setChatNotifications(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final s = r['notification_settings'];
    if (s is! Map) return _error(400, 'notification_settings required');
    final useDefault = s['use_default_mute_for'] == true;
    final muteFor = QlTdEngine._int(s['mute_for']) ?? 0;
    String muteUntil;
    int until;
    if (useDefault || muteFor <= 0) {
      muteUntil = '';
      until = 0;
    } else if (muteFor >= 366 * 86400) {
      muteUntil = 'forever';
      until = 253402300799;
    } else {
      final at = DateTime.now().toUtc().add(Duration(seconds: muteFor));
      muteUntil = at.toIso8601String();
      until = at.millisecondsSinceEpoch ~/ 1000;
    }
    final result = await _patchState(c, {'mute_until': muteUntil});
    if (result['@type'] == 'ok') {
      _applyDialog({'id': c.id, 'notification_mute_until': until}, emitChanges: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> _addChatToList(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final key = _listKey(r['chat_list']);
    if (key.startsWith('folder:')) {
      final fid = _folderIdByInt[int.tryParse(key.substring(7)) ?? 0];
      if (fid == null) return _error(404, 'Folder not found');
      final f = Map<String, dynamic>.from(_folders[fid] ?? {});
      final filter = Map<String, dynamic>.from(f['filter'] is Map ? f['filter'] as Map : {});
      final include = [for (final id in (filter['include_chat_ids'] as List? ?? const [])) id.toString()];
      if (!include.contains(c.id)) include.add(c.id);
      filter['include_chat_ids'] = include;
      await _apiOrThrow.patch('/folders/$fid', {'name': f['name'], 'filter': filter, 'sort_order': f['sort_order'] ?? 0});
      await _refreshFolders();
      return _ok;
    }
    final archived = key == 'archive';
    final result = await _patchState(c, {'archived': archived});
    if (result['@type'] == 'ok') {
      _applyDialog({'id': c.id, 'archived': archived}, emitChanges: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> _setDraft(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final draft = r['draft_message'];
    Map<String, dynamic>? text;
    if (draft is Map) {
      final content = draft['content'];
      if (content is Map && content['text'] is Map) {
        text = Map<String, dynamic>.from(content['text'] as Map);
      } else if (draft['input_message_text'] is Map) {
        final input = draft['input_message_text'] as Map;
        if (input['text'] is Map) text = Map<String, dynamic>.from(input['text'] as Map);
      }
    }
    final plain = text?['text']?.toString() ?? '';
    if (plain.isEmpty) {
      c.draft.remove('td');
    } else {
      c.draft['td'] = Map<String, dynamic>.from(draft as Map);
    }
    _emit({
      '@type': 'updateChatDraftMessage',
      'chat_id': c.chatId,
      'draft_message': c.draft['td'],
      'positions': [_position(c)],
    });
    if (c.id.startsWith('virtual:')) return _ok;
    try {
      await _apiOrThrow.patch(
        '/conversations/${c.id}/state',
        plain.isEmpty
            ? {'clear_draft': true}
            : {
                'draft': {'text': plain, 'entities': _backendEntities(text)},
              },
      );
    } catch (_) {
      // Drafts stay local when the backend rejects them (e.g. offline).
    }
    return _ok;
  }

  // MARK: Groups

  Map<String, dynamic> _memberStatus(String role) => switch (role) {
    'owner' => {'@type': 'chatMemberStatusCreator', 'custom_title': '', 'is_anonymous': false, 'is_member': true},
    'admin' => {
      '@type': 'chatMemberStatusAdministrator',
      'custom_title': '',
      'can_be_edited': false,
      'rights': {
        '@type': 'chatAdministratorRights',
        'can_manage_chat': true,
        'can_change_info': false,
        'can_post_messages': false,
        'can_edit_messages': false,
        'can_delete_messages': true,
        'can_invite_users': true,
        'can_restrict_members': true,
        'can_pin_messages': true,
        'can_manage_topics': false,
        'can_promote_members': false,
        'can_manage_video_chats': false,
        'can_post_stories': false,
        'can_edit_stories': false,
        'can_delete_stories': false,
        'can_manage_direct_messages': false,
        'can_manage_tags': false,
        'can_send_welcome_messages': false,
        'is_anonymous': false,
      },
    },
    _ => {'@type': 'chatMemberStatusMember', 'member_until_date': 0},
  };

  Map<String, dynamic> _basicGroup(_Conv c) => {
    '@type': 'basicGroup',
    'id': qlGroupInt(c.id),
    'member_count': c.members.length,
    'status': _memberStatus(c.role),
    'is_active': true,
    'upgraded_to_supergroup_id': 0,
  };

  _Conv? _groupByBasicId(int basicId) {
    for (final c in _convs.values) {
      if (c.isGroup && qlGroupInt(c.id) == basicId) return c;
    }
    return null;
  }

  Map<String, dynamic> _basicGroupById(int id) {
    final c = _groupByBasicId(id);
    if (c == null) return _error(400, 'Basic group not found');
    return _basicGroup(c);
  }

  Map<String, dynamic> _chatMember(Map<String, dynamic> m) => {
    '@type': 'chatMember',
    'member_id': _sender(m['user_id']?.toString() ?? ''),
    'tag': '',
    'inviter_user_id': 0,
    'joined_chat_date': 0,
    'status': _memberStatus(m['role']?.toString() ?? 'member'),
  };

  Future<Map<String, dynamic>> _basicGroupFullInfo(int id) async {
    final c = _groupByBasicId(id);
    if (c == null) return _error(400, 'Basic group not found');
    if (!c.membersLoaded) await _loadMembers(c);
    await Future.wait([
      for (final m in c.members.take(200)) _ensureUser(m['user_id']?.toString() ?? ''),
    ]);
    final owner = c.members.firstWhere(
      (m) => m['role'] == 'owner',
      orElse: () => const <String, dynamic>{},
    );
    return {
      '@type': 'basicGroupFullInfo',
      'photo': null,
      'description': '',
      'creator_user_id': qlUserInt(owner['user_id']?.toString() ?? ''),
      'members': [for (final m in c.members) _chatMember(m)],
      'can_hide_members': false,
      'can_toggle_aggressive_anti_spam': false,
      'invite_link': null,
      'bot_commands': const <Object>[],
    };
  }

  Future<Map<String, dynamic>> _getChatMember(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final member = r['member_id'];
    final uid = member is Map ? _userIdByInt[QlTdEngine._int(member['user_id']) ?? 0] : null;
    if (uid == null) return _error(400, 'Member not found');
    if (!c.membersLoaded && !c.id.startsWith('virtual:')) await _loadMembers(c);
    for (final m in c.members) {
      if (m['user_id'] == uid) return _chatMember(m);
    }
    if (!c.isGroup) return _chatMember({'user_id': uid, 'role': 'member'});
    return {
      '@type': 'chatMember',
      'member_id': _sender(uid),
      'tag': '',
      'inviter_user_id': 0,
      'joined_chat_date': 0,
      'status': {'@type': 'chatMemberStatusLeft'},
    };
  }

  Future<Map<String, dynamic>> _chatAdministrators(int chatId) async {
    final c = _conv(chatId);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    if (!c.membersLoaded) await _loadMembers(c);
    return {
      '@type': 'chatAdministrators',
      'administrators': [
        for (final m in c.members)
          if (m['role'] == 'owner' || m['role'] == 'admin')
            {
              '@type': 'chatAdministrator',
              'user_id': qlUserInt(m['user_id']?.toString() ?? ''),
              'custom_title': '',
              'is_owner': m['role'] == 'owner',
              'can_be_edited': false,
            },
      ],
    };
  }

  Future<Map<String, dynamic>> _changeMember(_Conv c, String uid, String action, [String? role]) async {
    await _apiOrThrow.post('/conversations/${c.id}/members', {
      'user_id': uid,
      'action': action,
      if (role != null) 'role': role,
    });
    try {
      await _loadMembers(c);
      _emit({'@type': 'updateBasicGroup', 'basic_group': _basicGroup(c)});
    } catch (_) {}
    return _ok;
  }

  Future<Map<String, dynamic>> _addChatMember(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final uid = _userIdByInt[QlTdEngine._int(r['user_id']) ?? 0];
    if (c == null || !c.isGroup || uid == null) return _error(400, 'Chat or user not found');
    await _changeMember(c, uid, 'add');
    return {'@type': 'failedToAddMembers', 'failed_to_add_members': const <Object>[]};
  }

  Future<Map<String, dynamic>> _addChatMembers(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    for (final v in (r['user_ids'] as List? ?? const [])) {
      final uid = _userIdByInt[QlTdEngine._int(v) ?? 0];
      if (uid != null) await _changeMember(c, uid, 'add');
    }
    return {'@type': 'failedToAddMembers', 'failed_to_add_members': const <Object>[]};
  }

  Future<Map<String, dynamic>> _setChatMemberStatus(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final member = r['member_id'];
    final uid = member is Map ? _userIdByInt[QlTdEngine._int(member['user_id']) ?? 0] : null;
    final status = r['status'];
    if (c == null || !c.isGroup || uid == null || status is! Map) {
      return _error(400, 'Chat or member not found');
    }
    switch (status['@type']) {
      case 'chatMemberStatusLeft':
      case 'chatMemberStatusBanned':
        return _changeMember(c, uid, 'remove');
      case 'chatMemberStatusAdministrator':
        return _changeMember(c, uid, 'role', 'admin');
      case 'chatMemberStatusMember':
        return _changeMember(c, uid, 'role', 'member');
      default:
        return _unsupported('setChatMemberStatus(${status['@type']})');
    }
  }

  Future<Map<String, dynamic>> _leaveChat(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    await _apiOrThrow.post('/conversations/${c.id}/members', {'user_id': _myId, 'action': 'remove'});
    _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c, removed: true)});
    return _ok;
  }

  // MARK: History

  Future<Map<String, dynamic>> _history(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final from = QlTdEngine._int(r['from_message_id']) ?? 0;
    final offset = math.min(0, QlTdEngine._int(r['offset']) ?? 0);
    final limit = (QlTdEngine._int(r['limit']) ?? 50).clamp(1, 100);
    final pendings = [
      for (final p in _pendingByTempId.values)
        if (p.conv == c) p.message,
    ];
    if (c.id.startsWith('virtual:')) {
      return {'@type': 'messages', 'total_count': pendings.length, 'messages': pendings.reversed.toList()};
    }
    List<Map<String, dynamic>> window;
    if (r['only_local'] == true) {
      window = _localWindow(c, from, offset, limit);
    } else {
      final fromSeq = from == 0 ? 0 : qlSeqOf(from);
      final newer = -offset;
      final before = from == 0 ? 0 : fromSeq + newer + 1;
      final result = await _apiOrThrow.get('/conversations/${c.id}/messages', {
        if (before > 0) 'before': '$before',
        'limit': '$limit',
      });
      final raw = <Map<String, dynamic>>[
        for (final m in (result['messages'] as List? ?? const []))
          if (m is Map) Map<String, dynamic>.from(m),
      ];
      await _prepareMessages(c, raw);
      window = [];
      for (final m in raw) {
        final td = _tdMessage(c, m);
        final seq = QlTdEngine._int(m['conversation_seq']) ?? 0;
        if (td == null) {
          c.messages.remove(seq);
          continue;
        }
        _cacheMessage(c, td, m);
        window.add(td);
      }
    }
    if (from == 0 && offset == 0) {
      window = [...pendings.reversed, ...window].take(limit).toList();
    }
    return {'@type': 'messages', 'total_count': window.length, 'messages': window};
  }

  List<Map<String, dynamic>> _localWindow(_Conv c, int from, int offset, int limit) {
    final desc = c.messages.values.toList().reversed.toList();
    if (desc.isEmpty) return [];
    var start = 0;
    if (from != 0) {
      start = desc.indexWhere((m) => (m['id'] as int) <= from);
      if (start < 0) return [];
    }
    start = math.max(0, start + offset);
    return desc.skip(start).take(limit).toList();
  }

  /// Makes sure senders are known and image sizes are available before the
  /// UI lays out a page (the backend stores no dimensions yet).
  void _indexMessageRefs(_Conv c, List<Map<String, dynamic>> raw) {
    for (final m in raw) {
      final id = m['id']?.toString() ?? '';
      final seq = QlTdEngine._int(m['conversation_seq']) ?? 0;
      if (id.isNotEmpty && seq > 0) {
        _messageRef[id] = (c.id, seq);
      }
    }
  }

  Future<void> _prepareMessages(_Conv c, List<Map<String, dynamic>> raw) async {
    _indexMessageRefs(c, raw);
    final senders = <String>{for (final m in raw) m['sender_id']?.toString() ?? ''}
      ..remove('');
    final missing = senders.where((s) => !_users.containsKey(s)).toList();
    final waits = <Future<void>>[for (final s in missing) _ensureUser(s)];
    for (final m in raw) {
      if (m['kind'] != 'image' || m['deleted'] == true) continue;
      final media = m['media_id']?.toString() ?? '';
      if (media.isEmpty || _mediaDims.containsKey(media)) continue;
      if (m['media'] is Map && (m['media'] as Map)['width'] != null) continue;
      _fileForMedia(media, kind: 'image');
      final f = _files[qlMediaFileId(media)]!;
      if (f.localPath.isNotEmpty) {
        _learnImageDims(media, f.localPath);
        continue;
      }
      f.download ??= _runDownload(f);
      waits.add(f.download!);
    }
    if (waits.isEmpty) return;
    try {
      await Future.wait(waits).timeout(const Duration(milliseconds: 2500));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _getMessage(int chatId, int messageId, {bool localOnly = false}) async {
    final c = _conv(chatId);
    if (c == null) return _error(400, 'Chat not found');
    final pending = _pendingByTempId[messageId];
    if (pending != null) return pending.message;
    final seq = qlSeqOf(messageId);
    final cached = c.messages[seq];
    if (cached != null && cached['id'] == messageId) return cached;
    if (localOnly || seq <= 0 || c.id.startsWith('virtual:')) return _error(404, 'Not Found');
    final result = await _apiOrThrow.get('/conversations/${c.id}/messages', {
      'before': '${seq + 1}',
      'limit': '1',
    });
    for (final m in (result['messages'] as List? ?? const [])) {
      if (m is! Map) continue;
      final raw = Map<String, dynamic>.from(m);
      if (QlTdEngine._int(raw['conversation_seq']) != seq) continue;
      await _prepareMessages(c, [raw]);
      final td = _tdMessage(c, raw);
      if (td == null) break;
      _cacheMessage(c, td, raw);
      return td;
    }
    return _error(404, 'Not Found');
  }

  Future<Map<String, dynamic>> _getMessages(Map<String, dynamic> r) async {
    final chatId = QlTdEngine._int(r['chat_id']) ?? 0;
    final out = <Map<String, dynamic>?>[];
    for (final v in (r['message_ids'] as List? ?? const [])) {
      final m = await _getMessage(chatId, QlTdEngine._int(v) ?? 0);
      out.add(m['@type'] == 'message' ? m : null);
    }
    return {'@type': 'messages', 'total_count': out.length, 'messages': out};
  }

  Future<Map<String, dynamic>> _getRepliedMessage(Map<String, dynamic> r) async {
    final chatId = QlTdEngine._int(r['chat_id']) ?? 0;
    final message = await _getMessage(chatId, QlTdEngine._int(r['message_id']) ?? 0);
    if (message['@type'] != 'message') return message;
    final reply = message['reply_to'];
    if (reply is! Map) return _error(404, 'Not Found');
    final target = QlTdEngine._int(reply['message_id']) ?? 0;
    if (target != 0) return _getMessage(chatId, target);
    final backendId = message['@ql_reply_to']?.toString() ?? '';
    final c = _conv(chatId);
    if (c == null || backendId.isEmpty) return _error(404, 'Not Found');
    // Walk back a few pages to find a reply target outside the cache.
    var before = qlSeqOf(message['id'] as int);
    for (var page = 0; page < 5 && before > 1; page++) {
      final result = await _apiOrThrow.get('/conversations/${c.id}/messages', {
        'before': '$before',
        'limit': '100',
      });
      final list = result['messages'] as List? ?? const [];
      if (list.isEmpty) break;
      for (final m in list) {
        if (m is! Map) continue;
        final raw = Map<String, dynamic>.from(m);
        final td = _tdMessage(c, raw);
        if (td != null) _cacheMessage(c, td, raw);
        before = math.min(before, QlTdEngine._int(raw['conversation_seq']) ?? before);
        if (raw['id'] == backendId) {
          return td ?? _error(404, 'Not Found');
        }
      }
    }
    return _error(404, 'Not Found');
  }

  Future<Map<String, dynamic>> _viewMessages(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) return _ok;
    var maxSeq = 0;
    for (final v in (r['message_ids'] as List? ?? const [])) {
      final id = QlTdEngine._int(v) ?? 0;
      if (id & 0xFFFFF != 0) continue; // pending local message
      maxSeq = math.max(maxSeq, qlSeqOf(id));
    }
    maxSeq = math.min(maxSeq, c.lastSeq);
    if (maxSeq <= c.readSeq && !(r['force_read'] == true && c.manualUnread)) return _ok;
    c.readSeq = math.max(c.readSeq, maxSeq);
    var unread = 0;
    for (final e in c.messages.entries) {
      if (e.key > c.readSeq && e.value['is_outgoing'] != true) unread++;
    }
    final unknownTail = c.lastSeq - (c.messages.isEmpty ? 0 : c.messages.lastKey()!);
    if (unknownTail > 0) unread = math.max(unread, math.min(c.unread, unknownTail));
    c.unread = math.min(c.unread, unread);
    _emit({
      '@type': 'updateChatReadInbox',
      'chat_id': c.chatId,
      'last_read_inbox_message_id': _lastReadInboxId(c),
      'unread_count': c.unread,
    });
    unawaited(_postRead(c, c.readSeq));
    return _ok;
  }

  Map<String, dynamic> _messageProperties(Map<String, dynamic> r) {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final m = c?.messages[qlSeqOf(id)] ?? _pendingByTempId[id]?.message;
    if (c == null || m == null) return _error(404, 'Not Found');
    final pending = _pendingByTempId.containsKey(id);
    final outgoing = m['is_outgoing'] == true;
    final admin = c.role == 'owner' || c.role == 'admin';
    final contentType = (m['content'] as Map?)?['@type'];
    final editable = outgoing && !pending &&
        (contentType == 'messageText' || contentType == 'messagePhoto' ||
            contentType == 'messageDocument' || contentType == 'messageVoiceNote');
    return {
      '@type': 'messageProperties',
      'can_add_offer': false,
      'can_add_tasks': false,
      'can_be_approved': false,
      'can_be_copied': true,
      'can_be_copied_to_secret_chat': false,
      'can_be_declined': false,
      'can_be_deleted_only_for_self': false,
      'can_be_deleted_for_all_users': outgoing || (c.isGroup && admin),
      'can_be_edited': editable,
      'can_be_forwarded': !pending,
      'can_be_paid': false,
      'can_be_pinned': !pending && (!c.isGroup || admin),
      'can_be_replied': !pending,
      'can_be_replied_in_another_chat': false,
      'can_be_saved': true,
      'can_be_shared_in_story': false,
      'can_delete_reactions': false,
      'can_edit_media': false,
      'can_edit_scheduling_state': false,
      'can_edit_suggested_post_info': false,
      'can_get_author': false,
      'can_get_embedding_code': false,
      'can_get_link': false,
      'can_get_media_timestamp_links': false,
      'can_get_message_thread': false,
      'can_get_poll_vote_statistics': false,
      'can_get_read_date': false,
      'can_get_statistics': false,
      'can_get_video_advertisements': false,
      'can_get_viewers': false,
      'can_mark_tasks_as_done': false,
      'can_recognize_speech': false,
      'can_report_chat': true,
      'can_report_reactions': false,
      'can_report_supergroup_spam': false,
      'can_set_fact_check': false,
      'custom_emoji_ids': const <int>[],
      'has_protected_content_by_current_user': false,
      'has_protected_content_by_other_user': false,
      'need_show_statistics': false,
    };
  }

  // MARK: Sending

  String? _inputFilePath(Object? input) {
    if (input is! Map) return null;
    switch (input['@type']) {
      case 'inputFileLocal':
        final path = input['path']?.toString() ?? '';
        return path.isEmpty ? null : path;
      case 'inputFileId':
        final f = _files[QlTdEngine._int(input['id']) ?? 0];
        return (f == null || f.localPath.isEmpty) ? null : f.localPath;
      default:
        return null;
    }
  }

  /// TDLib input content -> (backend send fields, local media path, local
  /// TDLib content for the pending bubble).
  ({String kind, String text, List<Map<String, dynamic>> entities, String? path, Map<String, dynamic> content})? _draftContent(Map<String, dynamic> input) {
    Map<String, dynamic>? captionOf(String key) =>
        input[key] is Map ? Map<String, dynamic>.from(input[key] as Map) : null;
    switch (input['@type']) {
      case 'inputMessageText':
        final text = captionOf('text');
        final plain = text?['text']?.toString() ?? '';
        if (plain.trim().isEmpty) return null;
        return (
          kind: 'text',
          text: plain,
          entities: _backendEntities(text),
          path: null,
          content: {
            '@type': 'messageText',
            'text': _formatted(plain, _tdEntities(plain, null)..addAll(const [])),
            'link_preview': null,
            'link_preview_options': null,
          },
        );
      case 'inputMessagePhoto':
        final path = _inputFilePath(input['photo']);
        if (path == null) return null;
        final caption = captionOf('caption');
        final plain = caption?['text']?.toString() ?? '';
        var w = QlTdEngine._int(input['width']) ?? 0;
        var h = QlTdEngine._int(input['height']) ?? 0;
        if (w <= 0 || h <= 0) {
          final size = qlImageSizeOfFile(path);
          if (size != null) {
            w = size.$1;
            h = size.$2;
          }
        }
        final local = _localFile(path)..kind = 'image';
        return (
          kind: 'image',
          text: plain,
          entities: _backendEntities(caption),
          path: path,
          content: {
            '@type': 'messagePhoto',
            'photo': {
              '@type': 'photo',
              'has_stickers': false,
              'minithumbnail': null,
              'sizes': [
                {
                  '@type': 'photoSize',
                  'type': 'x',
                  'photo': _tdFile(local),
                  'width': w,
                  'height': h,
                  'progressive_sizes': const <int>[],
                },
              ],
            },
            'caption': _formatted(plain, _tdEntities(plain, null)),
            'show_caption_above_media': false,
            'has_spoiler': false,
            'is_secret': false,
          },
        );
      case 'inputMessageDocument':
        final path = _inputFilePath(input['document']);
        if (path == null) return null;
        final caption = captionOf('caption');
        final plain = caption?['text']?.toString() ?? '';
        final local = _localFile(path);
        final name = path.split(Platform.pathSeparator).last;
        return (
          kind: 'file',
          text: plain,
          entities: _backendEntities(caption),
          path: path,
          content: {
            '@type': 'messageDocument',
            'document': {
              '@type': 'document',
              'file_name': name,
              'mime_type': 'application/octet-stream',
              'minithumbnail': null,
              'thumbnail': null,
              'document': _tdFile(local),
            },
            'caption': _formatted(plain, _tdEntities(plain, null)),
          },
        );
      case 'inputMessageVoiceNote':
        final path = _inputFilePath(input['voice_note']);
        if (path == null) return null;
        final caption = captionOf('caption');
        final plain = caption?['text']?.toString() ?? '';
        final local = _localFile(path)..kind = 'voice';
        return (
          kind: 'voice',
          text: plain,
          entities: _backendEntities(caption),
          path: path,
          content: {
            '@type': 'messageVoiceNote',
            'voice_note': {
              '@type': 'voiceNote',
              'duration': QlTdEngine._int(input['duration']) ?? 0,
              'waveform': input['waveform']?.toString() ?? '',
              'mime_type': 'audio/ogg',
              'speech_recognition_result': null,
              'voice': _tdFile(local),
            },
            'caption': _formatted(plain, _tdEntities(plain, null)),
            'is_listened': true,
          },
        );
      case 'inputMessageVideo':
        final path = _inputFilePath(input['video']);
        if (path == null) return null;
        final caption = captionOf('caption');
        final plain = caption?['text']?.toString() ?? '';
        final local = _localFile(path)..kind = 'video';
        final name = path.split(Platform.pathSeparator).last;
        return (
          kind: 'video',
          text: plain,
          entities: _backendEntities(caption),
          path: path,
          content: {
            '@type': 'messageVideo',
            'video': {
              '@type': 'video',
              'duration': QlTdEngine._int(input['duration']) ?? 0,
              'width': QlTdEngine._int(input['width']) ?? 0,
              'height': QlTdEngine._int(input['height']) ?? 0,
              'file_name': name.isEmpty ? 'video.mp4' : name,
              'mime_type': 'video/mp4',
              'has_stickers': false,
              'supports_streaming': true,
              'minithumbnail': null,
              'thumbnail': null,
              'video': _tdFile(local),
            },
            'alternative_videos': const <Object>[],
            'caption': _formatted(plain, _tdEntities(plain, null)),
            'show_caption_above_media': false,
            'has_spoiler': false,
            'is_secret': false,
          },
        );
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _sendMessage(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final input = r['input_message_content'];
    if (input is! Map) return _error(400, 'input_message_content required');
    final type = input['@type']?.toString() ?? '';
    if (type == 'inputMessageSticker') {
      return _sendStickerMessage(r, Map<String, dynamic>.from(input));
    }
    if (type == 'inputMessagePoll') {
      return _sendPollMessage(r, Map<String, dynamic>.from(input));
    }
    if (type == 'inputMessageChecklist') {
      return _sendChecklistMessage(r, Map<String, dynamic>.from(input));
    }
    final draft = _draftContent(Map<String, dynamic>.from(input));
    if (draft == null) {
      if (const {'inputMessageText', 'inputMessagePhoto', 'inputMessageDocument', 'inputMessageVoiceNote', 'inputMessageVideo'}.contains(type)) {
        return _error(400, 'MESSAGE_EMPTY');
      }
      return _unsupported('sendMessage($type)');
    }
    String replyTo = '';
    final reply = r['reply_to'];
    if (reply is Map && reply['@type'] == 'inputMessageReplyToMessage') {
      final target = QlTdEngine._int(reply['message_id']) ?? 0;
      final cached = c.messages[qlSeqOf(target)];
      replyTo = cached?['@ql_id']?.toString() ?? '';
    }
    final tempId = qlMessageId(c.lastSeq) + (++_pendingCounter % 0xFFFFE) + 1;
    final albumId = r['@ql_album_id']?.toString() ?? '';

    final clientMsgId = _newClientMsgId();
    final message = <String, dynamic>{
      '@type': 'message',
      'id': tempId,
      'sender_id': _sender(_myId),
      'chat_id': c.chatId,
      'sending_state': {'@type': 'messageSendingStatePending', 'sending_id': _pendingCounter},
      'scheduling_state': null,
      'is_outgoing': true,
      'is_pinned': false,
      'is_from_offline': false,
      'can_be_saved': true,
      'has_timestamped_media': false,
      'is_channel_post': false,
      'contains_unread_mention': false,
      'date': _nowSeconds(),
      'edit_date': 0,
      'forward_info': null,
      'import_info': null,
      'interaction_info': null,
      'unread_reactions': const <Object>[],
      'reply_to': replyTo.isEmpty
          ? null
          : {
              '@type': 'messageReplyToMessage',
              'chat_id': c.chatId,
              'message_id': QlTdEngine._int((reply as Map)['message_id']) ?? 0,
              'quote': null,
              'checklist_task_id': 0,
              'origin': null,
              'origin_send_date': 0,
              'content': null,
            },
      'topic_id': null,
      'self_destruct_type': null,
      'self_destruct_in': 0.0,
      'auto_delete_in': 0.0,
      'via_bot_user_id': 0,
      'sender_business_bot_user_id': 0,
      'sender_boost_count': 0,
      'paid_message_star_count': 0,
      'author_signature': '',
      'media_album_id': albumId.isEmpty ? 0 : _albumInt(albumId),
      'effect_id': 0,
      'restriction_info': null,
      'content': draft.content,
      if (albumId.isNotEmpty) '@ql_album_id': albumId,
      'reply_markup': null,
    };
    final pending = _Pending(conv: c, tempId: tempId, clientMsgId: clientMsgId, message: message);
    _pendingByClientId[clientMsgId] = pending;
    _pendingByTempId[tempId] = pending;
    _emit({'@type': 'updateNewMessage', 'message': message});
    c.lastMessage = message;
    if (c.id.startsWith('virtual:') && !c.announced) _announce(c);
    _emit({
      '@type': 'updateChatLastMessage',
      'chat_id': c.chatId,
      'last_message': message,
      'positions': [
        _position(c..lastActivityMicros = DateTime.now().microsecondsSinceEpoch),
      ],
    });
    unawaited(_deliver(pending, draft.kind, draft.text, draft.entities, draft.path, replyTo, albumId));
    return message;
  }

  Future<void> _deliver(
    _Pending p,
    String kind,
    String text,
    List<Map<String, dynamic>> entities,
    String? path,
    String replyTo, [
    String albumId = '',
  ]) async {
    try {
      var c = p.conv;
      if (c.id.startsWith('virtual:')) {
        c = await _materialize(c);
        _pendingByTempId[p.tempId] = _Pending(conv: c, tempId: p.tempId, clientMsgId: p.clientMsgId, message: p.message);
        _pendingByClientId[p.clientMsgId] = _pendingByTempId[p.tempId]!;
        p = _pendingByTempId[p.tempId]!;
      }
      var mediaId = '';
      if (path != null) {
        final headers = await _uploadHeadersFor(kind, path, p.message['content'] as Map?);
        final uploaded = await _apiOrThrow.uploadFile(path, conversationId: c.id, headers: headers);
        mediaId = uploaded['id']?.toString() ?? '';
        if (mediaId.isEmpty) throw const QlApiException(500, 'upload_failed');
        // Keep the local copy: no need to download what we just sent.
        final f = _files.putIfAbsent(qlMediaFileId(mediaId), () => _QlFile(qlMediaFileId(mediaId)));
        f
          ..mediaId = mediaId
          ..kind = kind == 'image' ? 'image' : (kind == 'voice' ? 'voice' : (kind == 'video' ? 'video' : 'file'))
          ..localPath = path
          ..size = await File(path).length();
        f.fileName = path.split(Platform.pathSeparator).last;
        if (kind == 'image') {
          final size = qlImageSizeOfFile(path);
          if (size != null) _mediaDims[mediaId] = [size.$1, size.$2];
        }
      }
      String previewId = '';
      if (kind == 'text') {
        final match = _urlPattern.firstMatch(text);
        if (match != null) {
          try {
            final preview = await _apiOrThrow.post('/link-previews', {'url': text.substring(match.start, match.end)});
            previewId = preview['id']?.toString() ?? '';
          } catch (_) {}
        }
      }
      final sent = await _apiOrThrow.post('/conversations/${c.id}/messages', {
        'client_msg_id': p.clientMsgId,
        'kind': kind,
        'text': text,
        'media_id': mediaId,
        'reply_to': replyTo,
        if (albumId.isNotEmpty) 'album_id': albumId,
        if (entities.isNotEmpty) 'entities': entities,
        if (previewId.isNotEmpty) 'link_preview_id': previewId,
      });
      _completePending(p, sent);
    } catch (e) {
      final code = e is QlApiException ? _tdCode(e.statusCode) : 500;
      final message = e is QlApiException ? _humanError(e) : '发送失败，请检查网络';
      final error = {'@type': 'error', 'code': code, 'message': message};
      p.message = {
        ...p.message,
        'sending_state': {
          '@type': 'messageSendingStateFailed',
          'error': error,
          'can_retry': true,
          'need_another_sender': false,
          'need_another_reply_quote': false,
          'need_drop_reply': false,
          'required_paid_message_star_count': 0,
          'retry_after': 0.0,
        },
      };
      p.message['@ql_retry'] = {'kind': kind, 'text': text, 'entities': entities, 'path': path, 'reply_to': replyTo, 'album_id': albumId};
      _emit({
        '@type': 'updateMessageSendFailed',
        'message': p.message,
        'old_message_id': p.tempId,
        'error': error,
      });
    }
  }

  void _completePending(_Pending p, Map<String, dynamic> raw) {
    if (p.done) return;
    p.done = true;
    _pendingByClientId.remove(p.clientMsgId);
    _pendingByTempId.remove(p.tempId);
    final c = _convs[raw['conversation_id']?.toString() ?? ''] ?? p.conv;
    final td = _tdMessage(c, raw);
    if (td == null) return;
    _cacheMessage(c, td, raw);
    _emit({'@type': 'updateMessageSendSucceeded', 'message': td, 'old_message_id': p.tempId});
    _advanceLast(c, td, incoming: false);
  }

  Future<Map<String, dynamic>> _resend(Map<String, dynamic> r) async {
    final out = <Map<String, dynamic>?>[];
    for (final v in (r['message_ids'] as List? ?? const [])) {
      final p = _pendingByTempId[QlTdEngine._int(v) ?? 0];
      final retry = p?.message['@ql_retry'];
      if (p == null || retry is! Map) {
        out.add(null);
        continue;
      }
      p.message = {
        ...p.message,
        'sending_state': {'@type': 'messageSendingStatePending', 'sending_id': ++_pendingCounter},
      }..remove('@ql_retry');
      _emit({'@type': 'updateNewMessage', 'message': p.message});
      unawaited(_deliver(
        p,
        retry['kind'] as String,
        retry['text'] as String,
        List<Map<String, dynamic>>.from(retry['entities'] as List),
        retry['path'] as String?,
        retry['reply_to'] as String,
        retry['album_id'] as String? ?? '',
      ));
      out.add(p.message);
    }
    return {'@type': 'messages', 'total_count': out.length, 'messages': out};
  }

  Future<Map<String, dynamic>> _sendAlbum(Map<String, dynamic> r) async {
    final albumId = 'alb${DateTime.now().microsecondsSinceEpoch}';
    final out = <Map<String, dynamic>>[];
    for (final content in (r['input_message_contents'] as List? ?? const [])) {
      final result = await _sendMessage({
        ...r,
        'input_message_content': content,
        '@ql_album_id': albumId,
      });
      if (result['@type'] != 'message') return result;
      out.add(result);
    }
    return {'@type': 'messages', 'total_count': out.length, 'messages': out};
  }

  Future<Map<String, dynamic>> _editText(Map<String, dynamic> r, {required bool caption}) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final cached = c.messages[qlSeqOf(id)];
    final backendId = cached?['@ql_id']?.toString() ?? '';
    if (backendId.isEmpty) return _error(400, 'Message not found');
    Map<String, dynamic>? text;
    if (caption) {
      if (r['caption'] is Map) text = Map<String, dynamic>.from(r['caption'] as Map);
    } else {
      final input = r['input_message_content'];
      if (input is Map && input['text'] is Map) text = Map<String, dynamic>.from(input['text'] as Map);
    }
    final plain = text?['text']?.toString() ?? '';
    if (!caption && plain.trim().isEmpty) return _error(400, 'MESSAGE_EMPTY');
    final result = await _apiOrThrow.patch('/messages/$backendId', {
      'text': plain,
      'entities': _backendEntities(text),
    });
    final td = _tdMessage(c, result);
    if (td == null) return _error(400, 'Message was deleted');
    await _onMessageEdited(c.id, result);
    return td;
  }

  Future<Map<String, dynamic>> _deleteMessages(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final removed = <int>[];
    for (final v in (r['message_ids'] as List? ?? const [])) {
      final id = QlTdEngine._int(v) ?? 0;
      final p = _pendingByTempId.remove(id);
      if (p != null) {
        _pendingByClientId.remove(p.clientMsgId);
        p.done = true;
        _emit({
          '@type': 'updateDeleteMessages',
          'chat_id': c.chatId,
          'message_ids': [id],
          'is_permanent': true,
          'from_cache': false,
        });
        continue;
      }
      final backendId = c.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
      if (backendId.isEmpty) continue;
      await _apiOrThrow.delete('/messages/$backendId');
      removed.add(qlSeqOf(id));
    }
    _removeMessages(c, removed);
    return _ok;
  }

  Map<String, dynamic> _sendChatAction(Map<String, dynamic> r) {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) return _ok;
    final action = r['action'];
    final typing = action is Map && action['@type'] != 'chatActionCancel';
    _sendFrame({
      'op': 'typing',
      'req_id': 't${DateTime.now().millisecondsSinceEpoch}',
      'conversation_id': c.id,
      'typing': typing,
    });
    return _ok;
  }

  Map<String, dynamic> _searchChatMessagesLocal(Map<String, dynamic> r) {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final filter = (r['filter'] as Map?)?['@type']?.toString() ?? 'searchMessagesFilterEmpty';
    final q = (r['query']?.toString() ?? '').trim().toLowerCase();
    if (q.isEmpty && filter == 'searchMessagesFilterEmpty') {
      return _unsupported('searchChatMessages(empty)');
    }
    final wanted = switch (filter) {
      'searchMessagesFilterEmpty' => null,
      'searchMessagesFilterPhoto' => const {'messagePhoto'},
      'searchMessagesFilterVideo' => const {'messageVideo'},
      'searchMessagesFilterPhotoAndVideo' => const {'messagePhoto', 'messageVideo'},
      'searchMessagesFilterDocument' => const {'messageDocument'},
      'searchMessagesFilterVoiceNote' || 'searchMessagesFilterVoiceAndVideoNote' => const {'messageVoiceNote'},
      _ => const <String>{'-'},
    };
    if (wanted != null && wanted.contains('-')) {
      return {'@type': 'foundChatMessages', 'total_count': 0, 'messages': const <Object>[], 'next_from_message_id': 0};
    }
    final from = QlTdEngine._int(r['from_message_id']) ?? 0;
    final limit = (QlTdEngine._int(r['limit']) ?? 50).clamp(1, 100);
    final out = <Map<String, dynamic>>[];
    for (final m in c.messages.values.toList().reversed) {
      if (from != 0 && (m['id'] as int) >= from) continue;
      final content = m['content'] as Map;
      if (wanted != null && !wanted.contains(content['@type'])) continue;
      if (q.isNotEmpty) {
        final text = ((content['text'] ?? content['caption']) as Map?)?['text']?.toString().toLowerCase() ?? '';
        if (!text.contains(q)) continue;
      }
      out.add(m);
      if (out.length >= limit) break;
    }
    return {
      '@type': 'foundChatMessages',
      'total_count': out.length,
      'messages': out,
      'next_from_message_id': out.length >= limit ? out.last['id'] : 0,
    };
  }


  // MARK: Users

  Future<Map<String, dynamic>> _getUser(int userInt) async {
    final id = _userIdByInt[userInt];
    if (id == null) return _error(404, 'User not found');
    if (!_users.containsKey(id)) await _ensureUser(id);
    return _tdUser(id);
  }

  Future<Map<String, dynamic>> _userFullInfo(int userInt) async {
    final id = _userIdByInt[userInt];
    if (id == null) return _error(404, 'User not found');
    final raw = _users[id];
    final avatar = raw?['avatar_media_id']?.toString() ?? '';
    final groupsInCommon = _convs.values.where(
      (c) => c.isGroup && c.members.any((m) => m['user_id'] == id),
    ).length;
    return {
      '@type': 'userFullInfo',
      'personal_photo': null,
      'photo': avatar.isEmpty ? null : _chatPhoto(avatar, raw),
      'public_photo': null,
      'community_id': 0,
      'block_list': _blockedUserIds.contains(id) ? {'@type': 'blockListMain'} : null,
      'can_be_called': false,
      'supports_video_calls': false,
      'has_private_calls': true,
      'has_private_forwards': false,
      'has_restricted_voice_and_video_note_messages': false,
      'has_posted_to_profile_stories': false,
      'has_sponsored_messages_enabled': false,
      'need_phone_number_privacy_exception': false,
      'set_chat_background': false,
      'uses_unofficial_app': false,
      'bio': _formatted(''),
      'birthdate': null,
      'personal_chat_id': 0,
      'gift_count': 0,
      'group_in_common_count': groupsInCommon,
      'incoming_paid_message_star_count': 0,
      'outgoing_paid_message_star_count': 0,
      'gift_settings': null,
      'bot_verification': null,
      'main_profile_tab': null,
      'first_profile_audio': null,
      'rating': null,
      'pending_rating': null,
      'pending_rating_date': 0,
      'note': null,
      'ton_wallet_card': null,
      'share_theme': null,
      'business_info': null,
      'bot_info': null,
    };
  }

  Map<String, dynamic> _chatPhoto(String mediaId, [Map<String, dynamic>? raw]) {
    final dims = _mediaDims[mediaId];
    final mime = _avatarMimeFor(mediaId, raw);
    _rememberAvatarMime(mediaId, mime);
    final file = _fileForMedia(mediaId, kind: 'avatar');
    final animation = avatarMimeUsesVideoPlayer(mime)
        ? {
            '@type': 'animatedChatPhoto',
            'length': dims?[0] ?? 640,
            'file': file,
            'main_frame_timestamp': 0.0,
          }
        : null;
    return {
      '@type': 'chatPhoto',
      'id': qlMediaFileId(mediaId),
      'added_date': 0,
      'minithumbnail': null,
      'sizes': [
        {
          '@type': 'photoSize',
          'type': 'x',
          'photo': file,
          'width': dims?[0] ?? 640,
          'height': dims?[1] ?? 640,
          'progressive_sizes': const <int>[],
        },
      ],
      'animation': animation,
      'small_animation': animation,
      'sticker': null,
    };
  }

  Map<String, dynamic> _userProfilePhotos(int userInt) {
    final id = _userIdByInt[userInt];
    if (id == null) return _error(404, 'User not found');
    final avatar = _users[id]?['avatar_media_id']?.toString() ?? '';
    return {
      '@type': 'chatPhotos',
      'total_count': avatar.isEmpty ? 0 : 1,
      'photos': [if (avatar.isNotEmpty) _chatPhoto(avatar, _users[id])],
    };
  }

  Future<Map<String, dynamic>> _patchMe({String? name, String? avatar}) async {
    final me = _users[_myId] ?? const <String, dynamic>{};
    final result = await _apiOrThrow.patch('/me', {
      'display_name': name ?? _displayName(me),
      'avatar_media_id': avatar ?? (me['avatar_media_id']?.toString() ?? ''),
    });
    _rememberUser(result);
    return _ok;
  }

  Future<Map<String, dynamic>> _setName(Map<String, dynamic> r) async {
    final name = [
      r['first_name']?.toString().trim() ?? '',
      r['last_name']?.toString().trim() ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    if (name.isEmpty) return _error(400, 'FIRSTNAME_INVALID');
    return _patchMe(name: name);
  }

  Future<Map<String, dynamic>> _setProfilePhoto(Map<String, dynamic> r) async {
    final photo = r['photo'];
    if (photo is! Map) {
      return _unsupported('setProfilePhoto(null)');
    }
    final type = photo['@type']?.toString();
    final path = switch (type) {
      'inputChatPhotoStatic' => _inputFilePath(photo['photo']),
      'inputChatPhotoAnimation' => _inputFilePath(photo['animation'] ?? photo['photo']),
      _ => null,
    };
    if (type != 'inputChatPhotoStatic' && type != 'inputChatPhotoAnimation') {
      return _unsupported('setProfilePhoto($type)');
    }
    if (path == null) return _error(400, 'PHOTO_INVALID');
    final uploaded = await _apiOrThrow.uploadFile(path);
    final mediaId = uploaded['id']?.toString() ?? '';
    if (mediaId.isEmpty) return _error(500, 'upload_failed');
    final mime = uploaded['mime']?.toString() ?? guessAvatarMimeFromPath(path);
    final f = _files.putIfAbsent(qlMediaFileId(mediaId), () => _QlFile(qlMediaFileId(mediaId)));
    f
      ..mediaId = mediaId
      ..kind = 'avatar'
      ..mime = mime
      ..localPath = path
      ..size = await File(path).length();
    final me = _users[_myId];
    if (me != null) {
      me['avatar_media_id'] = mediaId;
      me['avatar_mime'] = mime;
    }
    return _patchMe(avatar: mediaId);
  }

  Future<Map<String, dynamic>> _deleteProfilePhoto() => _patchMe(avatar: '');
}
