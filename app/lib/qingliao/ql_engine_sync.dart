part of 'ql_engine.dart';

extension on QlTdEngine {
  // MARK: Initial snapshot

  Future<void> _runInitialLoad() async {
    final api = _api;
    final session = _session;
    if (api == null || session == null) return;
    try {
      final me = await api.get('/me');
      _rememberUser(me);
    } on QlApiException catch (e) {
      if (e.statusCode == 401) {
        _sessionExpired();
        return;
      }
    } catch (_) {
      // Offline: keep going, the socket loop retries.
    }
    try {
      // Snapshot-then-resume: take the event high watermark first, then the
      // dialog snapshot, and resume the stream from that watermark. Events in
      // between are replayed and are idempotent against the snapshot.
      final sync = await api.get('/sync', {'after': '0', 'limit': '1'});
      final hw = QlTdEngine._int(sync['high_watermark']) ?? 0;
      session.eventCursor = hw;
      _ackedCursor = hw;
      await _loadConversations();
      await _refreshBlocks();
      await _loadP3Extras();
    } on QlApiException catch (e) {
      if (e.statusCode == 401) {
        _sessionExpired();
        return;
      }
    } catch (_) {}
    _ensureSocket(immediate: true);
  }

  Future<void> _loadConversations() async {
    final api = _apiOrThrow;
    String cursor = '';
    final fresh = <_Conv>[];
    for (var page = 0; page < 20; page++) {
      final query = <String, String>{'limit': '100', 'archived': 'all'};
      if (cursor.isNotEmpty) query['cursor'] = cursor;
      final result = await api.get('/conversations', query);
      final list = result['conversations'];
      if (list is List) {
        for (final d in list) {
          if (d is! Map) continue;
          final c = _applyDialog(Map<String, dynamic>.from(d), emitChanges: false);
          if (c != null) fresh.add(c);
        }
      }
      cursor = result['next_cursor']?.toString() ?? '';
      if (result['has_more'] != true || cursor.isEmpty) break;
    }
    await _hydrate(fresh);
  }

  /// Loads members/peers for conversations and announces them to the UI.
  Future<void> _hydrate(List<_Conv> convs) async {
    final queue = Queue<_Conv>.of(convs.where((c) => !c.membersLoaded));
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final c = queue.removeFirst();
        try {
          await _loadMembers(c);
        } catch (_) {}
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
    for (final c in convs) {
      if (c.announced) {
        _publishAnnouncedChat(c);
      } else {
        _announce(c);
      }
    }
    _schedulePersist();
  }

  Future<void> _loadMembers(_Conv c) async {
    final result = await _apiOrThrow.get('/conversations/${c.id}/members');
    final list = result['members'];
    final members = <Map<String, dynamic>>[];
    if (list is List) {
      for (final m in list) {
        if (m is Map) members.add(Map<String, dynamic>.from(m));
      }
    }
    c.members = members;
    c.membersLoaded = true;
    var peerRead = 0;
    for (final m in members) {
      final uid = m['user_id']?.toString() ?? '';
      if (uid == _myId) continue;
      final read = QlTdEngine._int(m['last_read_seq']);
      if (read != null && read > peerRead) peerRead = read;
      if (!c.isGroup) c.peerId = uid;
    }
    c.peerReadSeq = math.max(c.peerReadSeq, peerRead);
    final userIds = <String>{
      for (final m in members) m['user_id']?.toString() ?? '',
    }..remove('');
    // Groups can be large; load names lazily beyond the first 30.
    await Future.wait([
      for (final uid in userIds.take(c.isGroup ? 30 : 2)) _ensureUser(uid),
    ]);
    _assignChatId(c);
  }

  void _assignChatId(_Conv c) {
    final id = c.isGroup ? -qlGroupInt(c.id) : qlUserInt(c.peerId ?? '');
    if (id == 0) return;
    if (c.chatId != 0 && c.chatId != id) _convByChatId.remove(c.chatId);
    c.chatId = id;
    _convByChatId[id] = c;
  }

  void _announce(_Conv c) {
    if (c.chatId == 0) _assignChatId(c);
    if (c.chatId == 0) return;
    if (_isSelfConv(c)) return;
    if (!c.announced) {
      c.announced = true;
      if (c.isChannel) {
        _emit({'@type': 'updateSupergroup', 'supergroup': _supergroup(c)});
      } else if (c.isGroup) {
        _emit({'@type': 'updateBasicGroup', 'basic_group': _basicGroup(c)});
      }
      _emit({'@type': 'updateNewChat', 'chat': _tdChat(c)});
    }
  }

  /// Applies a dialog summary (list item or dialog.updated payload).
  _Conv? _applyDialog(Map<String, dynamic> d, {required bool emitChanges}) {
    final id = d['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final c = _convs.putIfAbsent(id, () => _Conv(id));
    final beforeOrder = c.announced ? _chatOrder(c) : -1;
    final beforeArchived = c.archived;
    final beforePinned = c.pinnedOrder;
    final beforeUnread = c.unread;
    final beforeReadInbox = c.announced ? _lastReadInboxId(c) : -1;
    final beforeMute = c.muteUntil;
    final beforeManual = c.manualUnread;
    final beforeOutbox = c.announced ? _lastReadOutboxId(c) : -1;

    if (d['kind'] != null) c.kind = d['kind'].toString();
    if (d['title'] != null) c.title = d['title'].toString();
    if (d['avatar_media_id'] != null) c.avatarMediaId = d['avatar_media_id'].toString();
    if (d['avatar'] != null && (d['avatar_media_id'] == null)) c.avatarMediaId = d['avatar'].toString();
    if (d['last_seq'] != null) c.lastSeq = math.max(c.lastSeq, QlTdEngine._int(d['last_seq']) ?? 0);
    if (d['last_activity'] != null) {
      c.lastActivityMicros = QlTdEngine._int(d['last_activity']) ?? c.lastActivityMicros;
    }
    if (d['last_read_seq'] != null) c.readSeq = QlTdEngine._int(d['last_read_seq']) ?? c.readSeq;
    if (d['role'] != null) c.role = d['role'].toString();
    if (d['archived'] != null) c.archived = d['archived'] == true;
    if (d['pinned_order'] != null) c.pinnedOrder = QlTdEngine._int(d['pinned_order']) ?? 0;
    if (d['notification_mute_until'] != null) {
      c.muteUntil = QlTdEngine._int(d['notification_mute_until']) ?? 0;
    }
    if (d['manual_unread'] != null) c.manualUnread = d['manual_unread'] == true;
    if (d['unread_count'] != null) c.unread = QlTdEngine._int(d['unread_count']) ?? 0;
    if (d['unread_mention_count'] != null) {
      c.mentions = QlTdEngine._int(d['unread_mention_count']) ?? 0;
    }
    if (d.containsKey('read_receipts_visible')) {
      c.readReceiptsVisible = d['read_receipts_visible'] != false;
    }
    if (d.containsKey('last_message_read_count')) {
      c.lastMessageReadCount = QlTdEngine._int(d['last_message_read_count']);
    }
    var lastChanged = false;
    if (d.containsKey('last_message')) {
      final brief = d['last_message'];
      if (brief is Map) {
        final b = Map<String, dynamic>.from(brief);
        final seq = QlTdEngine._int(b['conversation_seq']) ?? 0;
        c.lastSeq = math.max(c.lastSeq, seq);
        final current = c.lastMessage == null ? -1 : qlSeqOf(c.lastMessage!['id'] as int);
        if (seq != current || b['deleted'] == true || (b['edited_at']?.toString() ?? '').isNotEmpty) {
          if (c.chatId == 0 && !c.isGroup) {
            // Chat id unknown until members load; recompute at announce time.
          }
          c.lastMessage = _lastMessageFromBrief(c, b);
          lastChanged = true;
        }
      } else if (brief == null && d.containsKey('last_message') && emitChanges) {
        c.lastMessage = null;
        lastChanged = true;
      }
    }
    if (c.chatId != 0 && c.lastMessage != null && c.lastMessage!['chat_id'] != c.chatId) {
      c.lastMessage!['chat_id'] = c.chatId;
    }
    if (!emitChanges || !c.announced) return c;

    if (lastChanged) {
      _emit({
        '@type': 'updateChatLastMessage',
        'chat_id': c.chatId,
        'last_message': c.lastMessage,
        'positions': [_position(c)],
      });
    }
    if (beforeArchived != c.archived) {
      final old = _Conv(c.id)..archived = beforeArchived;
      _emit({
        '@type': 'updateChatPosition',
        'chat_id': c.chatId,
        'position': {..._position(old, removed: true)},
      });
      _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c)});
    } else if (beforeOrder != _chatOrder(c) || beforePinned != c.pinnedOrder) {
      _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c)});
    }
    if (beforeUnread != c.unread || beforeReadInbox != _lastReadInboxId(c)) {
      _emit({
        '@type': 'updateChatReadInbox',
        'chat_id': c.chatId,
        'last_read_inbox_message_id': _lastReadInboxId(c),
        'unread_count': c.unread,
      });
    }
    if (beforeOutbox != _lastReadOutboxId(c)) {
      _emit({
        '@type': 'updateChatReadOutbox',
        'chat_id': c.chatId,
        'last_read_outbox_message_id': _lastReadOutboxId(c),
      });
    }
    if (beforeMute != c.muteUntil) {
      _emit({
        '@type': 'updateChatNotificationSettings',
        'chat_id': c.chatId,
        'notification_settings': _notificationSettings(c),
      });
    }
    if (beforeManual != c.manualUnread) {
      _emit({
        '@type': 'updateChatIsMarkedAsUnread',
        'chat_id': c.chatId,
        'is_marked_as_unread': c.manualUnread,
      });
    }
    return c;
  }

  // MARK: WebSocket

  void _setConnection(String state) {
    if (_connectionState == state) return;
    _connectionState = state;
    _emit({
      '@type': 'updateConnectionState',
      'state': {'@type': state},
    });
  }

  void _ensureSocket({bool immediate = false}) {
    if (_closed || _session == null || _api == null) return;
    if (_socket != null || _connecting) return;
    _reconnectTimer?.cancel();
    if (immediate) {
      _backoffSeconds = 1;
      unawaited(_connect());
    } else {
      final delay = Duration(seconds: _backoffSeconds);
      _backoffSeconds = math.min(_backoffSeconds * 2, 30);
      _reconnectTimer = Timer(delay, () => unawaited(_connect()));
    }
  }

  Future<void> _connect() async {
    final api = _api;
    final session = _session;
    if (api == null || session == null || _closed || _connecting) return;
    _connecting = true;
    final generation = ++_socketGeneration;
    _setConnection(
      _backoffSeconds > 4 ? 'connectionStateWaitingForNetwork' : 'connectionStateConnecting',
    );
    try {
      final ws = await api.connectWebSocket(
        api.webSocketUri,
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (generation != _socketGeneration || _closed) {
        await ws.close();
        return;
      }
      ws.pingInterval = const Duration(seconds: 25);
      _socket = ws;
      ws.listen(
        (data) {
          if (generation != _socketGeneration) return;
          if (data is String) _onFrame(data);
        },
        onDone: () => _onSocketClosed(generation),
        onError: (_) => _onSocketClosed(generation),
        cancelOnError: true,
      );
    } on WebSocketException catch (e) {
      if (e.message.contains('401')) {
        _connecting = false;
        await _probeSession();
        return;
      }
      _ensureSocket();
    } catch (_) {
      _ensureSocket();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _probeSession() async {
    try {
      await _apiOrThrow.get('/me');
      _ensureSocket();
    } on QlApiException catch (e) {
      if (e.statusCode == 401) {
        _sessionExpired();
      } else {
        _ensureSocket();
      }
    } catch (_) {
      _ensureSocket();
    }
  }

  void _onSocketClosed(int generation) {
    if (generation != _socketGeneration) return;
    _socket = null;
    _ackTimer?.cancel();
    if (_closed) return;
    _setConnection('connectionStateConnecting');
    _ensureSocket();
  }

  void _sendFrame(Map<String, dynamic> frame) {
    final ws = _socket;
    if (ws == null) return;
    try {
      ws.add(jsonEncode({'v': 1, ...frame}));
    } catch (_) {}
  }

  void _onFrame(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final frame = Map<String, dynamic>.from(decoded);
    switch (frame['op']) {
      case 'hello':
        _sendFrame({
          'op': 'sync.resume',
          'req_id': 'resume',
          'after_event_seq': _session?.eventCursor ?? 0,
        });
        _backoffSeconds = 1;
        _setConnection('connectionStateReady');
      case 'event':
        final seq = QlTdEngine._int(frame['event_seq']) ?? 0;
        // Serialize event handling; some handlers await network lookups.
        _eventChain = _eventChain.then((_) async {
          try {
            await _onEvent(frame);
          } catch (_) {}
          final session = _session;
          if (session != null && seq > session.eventCursor) {
            session.eventCursor = seq;
            _scheduleAck();
          }
        });
      case 'typing':
        _onTyping(frame);
      case 'presence':
        _onPresence(frame);
      default:
        break;
    }
  }

  void _scheduleAck() {
    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(milliseconds: 300), () {
      final cursor = _session?.eventCursor ?? 0;
      if (cursor <= _ackedCursor) return;
      _ackedCursor = cursor;
      _sendFrame({
        'op': 'event.ack',
        'req_id': 'ack$cursor',
        'last_persisted_event_seq': cursor,
      });
      _schedulePersist();
    });
  }

  void _sessionExpired() {
    _teardown();
    try {
      File(_sessionPath).deleteSync();
    } catch (_) {}
    _session = null;
    _setAuth('authorizationStateWaitPhoneNumber');
  }

  // MARK: Ephemeral frames

  void _onTyping(Map<String, dynamic> f) {
    final c = _convs[f['conversation_id']?.toString() ?? ''];
    final uid = f['user_id']?.toString() ?? '';
    if (c == null || !c.announced || uid.isEmpty || uid == _myId) return;
    final typing = f['typing'] == true;
    final key = '${c.id}/$uid';
    _typingTimers.remove(key)?.cancel();
    void emitAction(bool on) => _emit({
      '@type': 'updateChatAction',
      'chat_id': c.chatId,
      'topic_id': null,
      'sender_id': _sender(uid),
      'action': {'@type': on ? 'chatActionTyping' : 'chatActionCancel'},
    });
    emitAction(typing);
    if (typing) {
      final seconds = QlTdEngine._int(f['expires_in']) ?? 5;
      _typingTimers[key] = Timer(Duration(seconds: seconds + 1), () {
        _typingTimers.remove(key);
        emitAction(false);
      });
    }
  }

  void _onPresence(Map<String, dynamic> f) {
    final uid = f['user_id']?.toString() ?? '';
    if (uid.isEmpty || uid == _myId) return;
    final raw = _users.putIfAbsent(uid, () => {'id': uid});
    raw['online'] = f['online'] == true;
    if (f['last_seen'] != null) raw['last_seen'] = f['last_seen'];
    _userIdByInt[qlUserInt(uid)] = uid;
    _emit({
      '@type': 'updateUserStatus',
      'user_id': qlUserInt(uid),
      'status': _userStatus(raw),
    });
  }

  // MARK: Durable events

  Future<void> _onEvent(Map<String, dynamic> ev) async {
    final type = ev['type']?.toString() ?? '';
    final cid = ev['conversation_id']?.toString() ?? '';
    final data = ev['data'] is Map ? Map<String, dynamic>.from(ev['data'] as Map) : <String, dynamic>{};
    switch (type) {
      case 'message.created':
        await _onMessageCreated(cid, data);
      case 'message.edited':
        await _onMessageEdited(cid, data);
      case 'message.deleted':
        _onMessageDeleted(cid, data);
      case 'messages.deleted':
        _onMessagesDeletedBySender(cid, data);
      case 'read.updated':
        _onReadUpdated(cid, data);
      case 'dialog.updated':
        final c = _convs[data['id']?.toString() ?? cid];
        if (c == null) {
          await _discoverConversation(data['id']?.toString() ?? cid);
        } else {
          _applyDialog(data, emitChanges: true);
        }
      case 'dialog.removed':
        final c = _convs[data['id']?.toString() ?? cid];
        if (c != null && c.announced) {
          _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c, removed: true)});
        }
      case 'conversation.created':
        await _discoverConversation(cid);
      case 'membership.changed':
        final c = _convs[cid];
        if (c == null) {
          await _discoverConversation(cid);
        } else {
          try {
            await _loadMembers(c);
          } catch (_) {}
          if (c.isChannel) {
            _emit({'@type': 'updateSupergroup', 'supergroup': _supergroup(c)});
          } else if (c.isGroup) {
            _emit({'@type': 'updateBasicGroup', 'basic_group': _basicGroup(c)});
          }
        }
      case 'reaction.updated':
        _onReactionUpdated(cid, data);
      case 'message.pinned':
        _onPinned(cid, data, remove: false);
      case 'message.unpinned':
        _onPinned(cid, data, remove: true);
      case 'conversation.cleared':
        final cleared = _convs[cid];
        if (cleared != null) {
          _applyCleared(cleared, throughSeq: QlTdEngine._int(data['through_seq']) ?? cleared.lastSeq);
        }
      case 'story.created':
      case 'story.updated':
      case 'story.deleted':
        _onStoryEvent(type, data);
      case 'folder.updated':
      case 'folder.deleted':
        unawaited(_refreshFolders());
      case 'user.updated':
          // A peer renamed themselves or changed their avatar. _rememberUser
          // emits updateUser plus updateChatTitle/updateChatPhoto for every
          // direct chat, which is what the list and the chat header listen to.
          final uid = data['id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            final current = Map<String, dynamic>.from(
              _users[uid] ?? {'id': uid},
            );
            if (data['display_name'] != null) {
              current['display_name'] = data['display_name'];
            }
            if (data['avatar_media_id'] != null) {
              current['avatar_media_id'] = data['avatar_media_id'];
            }
            if (data['avatar_mime'] != null) {
              current['avatar_mime'] = data['avatar_mime'];
            }
            _rememberUser(current);
          }
      case 'block.updated':
        final uid = data['user_id']?.toString() ?? '';
        if (uid.isNotEmpty) {
          if (data['blocked'] == true) {
            _blockedUserIds.add(uid);
          } else {
            _blockedUserIds.remove(uid);
          }
          _emit({
            '@type': 'updateMessageSenderBlockList',
            'sender_id': {'@type': 'messageSenderUser', 'user_id': qlUserInt(uid)},
            'block_list': data['blocked'] == true ? {'@type': 'blockListMain'} : null,
          });
        }
      default:
        // pins.changed, moderation.updated, folder.*, privacy.*: later.
        break;
    }
  }

  Future<_Conv?> _discoverConversation(String cid) async {
    if (cid.isEmpty) return null;
    final existing = _convs[cid];
    if (existing != null && existing.announced) return existing;
    // No single-dialog endpoint: re-read the first page (most recent first).
    final result = await _apiOrThrow.get('/conversations', {'limit': '50', 'archived': 'all'});
    final list = result['conversations'];
    final found = <_Conv>[];
    if (list is List) {
      for (final d in list) {
        if (d is! Map) continue;
        final id = d['id']?.toString() ?? '';
        final known = _convs[id];
        if (known != null && known.announced) {
          _applyDialog(Map<String, dynamic>.from(d), emitChanges: true);
          continue;
        }
        final c = _applyDialog(Map<String, dynamic>.from(d), emitChanges: false);
        if (c != null) found.add(c);
      }
    }
    await _hydrate(found);
    return _convs[cid];
  }

  Future<_Conv?> _convFor(String cid) async {
    final c = _convs[cid];
    if (c != null && c.announced) return c;
    return _discoverConversation(cid);
  }

  Future<void> _onMessageCreated(String cid, Map<String, dynamic> m) async {
    final c = await _convFor(cid.isEmpty ? m['conversation_id']?.toString() ?? '' : cid);
    if (c == null) return;
    final td = _tdMessage(c, m);
    if (td == null) return;
    final seq = qlSeqOf(td['id'] as int);
    final sender = m['sender_id']?.toString() ?? '';
    if (sender == _myId) {
      final pending = _pendingByClientId[m['client_msg_id']?.toString() ?? ''];
      if (pending != null) {
        _completePending(pending, m);
        return;
      }
    }
    if (c.messages.containsKey(seq)) return;
    if (!_users.containsKey(sender)) await _ensureUser(sender);
    _cacheMessage(c, td, m);
    _emit({'@type': 'updateNewMessage', 'message': td});
    _advanceLast(c, td, incoming: sender != _myId);
  }

  void _advanceLast(_Conv c, Map<String, dynamic> td, {required bool incoming}) {
    final seq = qlSeqOf(td['id'] as int);
    final currentLast = c.lastMessage == null ? 0 : qlSeqOf(c.lastMessage!['id'] as int);
    if (seq < currentLast) return;
    final isNew = seq > c.lastSeq || seq > currentLast;
    c.lastSeq = math.max(c.lastSeq, seq);
    c.lastActivityMicros = math.max(
      c.lastActivityMicros,
      ((td['date'] as int?) ?? _nowSeconds()) * 1000000,
    );
    c.lastMessage = td;
    _emit({
      '@type': 'updateChatLastMessage',
      'chat_id': c.chatId,
      'last_message': td,
      'positions': [_position(c)],
    });
    if (incoming && isNew && seq > c.readSeq) {
      c.unread += 1;
      _emit({
        '@type': 'updateChatReadInbox',
        'chat_id': c.chatId,
        'last_read_inbox_message_id': _lastReadInboxId(c),
        'unread_count': c.unread,
      });
    } else if (!incoming && c.unread == 0 && seq > c.readSeq) {
      // Like Telegram: sending into a fully read chat keeps it fully read.
      c.readSeq = seq;
      unawaited(_postRead(c, seq));
    }
  }

  Future<void> _onMessageEdited(String cid, Map<String, dynamic> m) async {
    final c = _convs[cid.isEmpty ? m['conversation_id']?.toString() ?? '' : cid];
    if (c == null || !c.announced) return;
    final td = _tdMessage(c, m);
    if (td == null) {
      _onMessageDeleted(cid, m);
      return;
    }
    _cacheMessage(c, td, m);
    _emit({
      '@type': 'updateMessageContent',
      'chat_id': c.chatId,
      'message_id': td['id'],
      'new_content': td['content'],
    });
    _emit({
      '@type': 'updateMessageEdited',
      'chat_id': c.chatId,
      'message_id': td['id'],
      'edit_date': td['edit_date'],
      'reply_markup': null,
    });
    if (c.lastMessage != null && c.lastMessage!['id'] == td['id']) {
      c.lastMessage = td;
      _emit({
        '@type': 'updateChatLastMessage',
        'chat_id': c.chatId,
        'last_message': td,
        'positions': [_position(c)],
      });
    }
  }

  void _onMessageDeleted(String cid, Map<String, dynamic> m) {
    final msgId = m['id']?.toString() ?? '';
    final ref = _messageRef[msgId];
    final c = _convs[cid.isNotEmpty ? cid : (ref?.$1 ?? '')];
    if (c == null || !c.announced) return;
    final seq = QlTdEngine._int(m['conversation_seq']) ?? ref?.$2;
    if (seq == null) return;
    _removeMessages(c, [seq]);
  }

  void _onMessagesDeletedBySender(String cid, Map<String, dynamic> d) {
    final c = _convs[cid];
    if (c == null || !c.announced) return;
    final sender = d['sender_id']?.toString() ?? '';
    final through = QlTdEngine._int(d['through_seq']) ?? 0;
    final seqs = [
      for (final e in c.messages.entries)
        if (e.key <= through &&
            ((e.value['sender_id'] as Map)['user_id'] == qlUserInt(sender)))
          e.key,
    ];
    _removeMessages(c, seqs);
  }

  void _removeMessages(_Conv c, List<int> seqs) {
    if (seqs.isEmpty) return;
    for (final s in seqs) {
      c.messages.remove(s);
    }
    _emit({
      '@type': 'updateDeleteMessages',
      'chat_id': c.chatId,
      'message_ids': [for (final s in seqs) qlMessageId(s)],
      'is_permanent': true,
      'from_cache': false,
    });
    final last = c.lastMessage;
    if (last != null && seqs.contains(qlSeqOf(last['id'] as int))) {
      final previous = c.messages.isEmpty ? null : c.messages[c.messages.lastKey()];
      c.lastMessage = previous;
      _emit({
        '@type': 'updateChatLastMessage',
        'chat_id': c.chatId,
        'last_message': previous,
        'positions': [_position(c)],
      });
    }
  }

  void _onReadUpdated(String cid, Map<String, dynamic> d) {
    final c = _convs[cid];
    if (c == null || !c.announced) return;
    final uid = d['user_id']?.toString() ?? '';
    final seq = QlTdEngine._int(d['last_read_seq']) ?? 0;
    if (uid == _myId) {
      if (seq > c.readSeq) c.readSeq = seq;
      return; // unread_count arrives with dialog.updated
    }
    if (seq <= c.peerReadSeq) return;
    c.peerReadSeq = seq;
    for (final m in c.members) {
      if (m['user_id'] == uid) m['last_read_seq'] = seq;
    }
    _emit({
      '@type': 'updateChatReadOutbox',
      'chat_id': c.chatId,
      'last_read_outbox_message_id': _lastReadOutboxId(c),
    });
  }

  Future<void> _postRead(_Conv c, int seq) async {
    try {
      await _apiOrThrow.post('/conversations/${c.id}/read', {'last_read_seq': seq});
    } catch (_) {}
  }
}
