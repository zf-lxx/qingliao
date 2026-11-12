part of 'ql_engine.dart';

extension on QlTdEngine {
  // MARK: P2 — media albums, search, forward, pin, reactions, block, report,
  // groups/channels (title, avatar, create).

  static const _reportOptions = <(String, String)>[
    ('spam', '垃圾信息或广告'),
    ('abuse', '骚扰或辱骂'),
    ('illegal', '违法违规内容'),
    ('other', '其他'),
  ];

  static const _reactionEmojis = <String>[
    '👍',
    '👎',
    '❤️',
    '🔥',
    '🥰',
    '👏',
    '😁',
    '🤔',
    '🎉',
    '🙏',
    '😂',
    '😢',
    '😮',
    '💯',
  ];

  int _albumInt(String albumId) {
    if (albumId.isEmpty) return 0;
    return _fnv1a64('a:$albumId') & 0x7FFFFFFFFFFFFFFF;
  }

  int _durationSec(Map<String, dynamic> meta, [Object? fallback]) {
    final ms = QlTdEngine._int(meta['duration_ms']);
    if (ms != null && ms > 0) return (ms / 1000).ceil();
    return QlTdEngine._int(meta['duration']) ?? QlTdEngine._int(fallback) ?? 0;
  }

  Map<String, dynamic>? _forwardInfo(Map<String, dynamic> m) {
    var origin = m['forward_origin'];
    if (origin is String && origin.isNotEmpty) {
      try {
        origin = jsonDecode(origin);
      } catch (_) {
        return null;
      }
    }
    if (origin is! Map) return null;
    final o = Map<String, dynamic>.from(origin);
    final sender = o['sender_id']?.toString() ?? '';
    final title = o['chat_title']?.toString() ?? '';
    final date = _parseDate(o['created_at']?.toString() ?? '');
    final srcChat = o['conversation_id']?.toString() ?? '';
    final srcConv = _convs[srcChat];
    Map<String, dynamic> tdOrigin;
    if (title.isNotEmpty) {
      tdOrigin = {
        '@type': srcConv != null && srcConv.isChannel
            ? 'messageOriginChannel'
            : 'messageOriginChat',
        'chat_id': srcConv?.chatId ?? 0,
        if (srcConv != null && srcConv.isChannel) 'author_signature': o['sender_name'] ?? '',
        'sender_user_id': sender.isEmpty ? 0 : qlUserInt(sender),
      };
    } else if (sender.isNotEmpty) {
      tdOrigin = {
        '@type': 'messageOriginUser',
        'sender_user_id': qlUserInt(sender),
      };
    } else {
      tdOrigin = {
        '@type': 'messageOriginHiddenUser',
        'sender_name': o['sender_name']?.toString() ?? '转发',
      };
    }
    final srcSeq = QlTdEngine._int(o['conversation_seq']);
    return {
      '@type': 'messageForwardInfo',
      'origin': tdOrigin,
      'date': date,
      'source': srcConv == null || srcSeq == null
          ? null
          : {
              '@type': 'forwardSource',
              'chat_id': srcConv.chatId,
              'message_id': qlMessageId(srcSeq),
              'sender_id': sender.isEmpty ? null : _sender(sender),
              'sender_name': o['sender_name']?.toString() ?? '',
              'date': date,
              'is_outgoing': false,
            },
      'public_service_announcement_type': '',
    };
  }

  Map<String, dynamic>? _interactionInfo(_Conv c, int seq) {
    final list = c.reactionsBySeq[seq];
    if (list == null || list.isEmpty) return null;
    final grouped = <String, List<Map<String, String>>>{};
    for (final r in list) {
      final emoji = r['emoji'] ?? '';
      if (emoji.isEmpty) continue;
      grouped.putIfAbsent(emoji, () => []).add(r);
    }
    return {
      '@type': 'messageInteractionInfo',
      'view_count': 0,
      'forward_count': 0,
      'reply_info': null,
      'reactions': {
        '@type': 'messageReactions',
        'reactions': [
          for (final e in grouped.entries)
            {
              '@type': 'messageReaction',
              'type': {'@type': 'reactionTypeEmoji', 'emoji': e.key},
              'total_count': e.value.length,
              'is_chosen': e.value.any((r) => r['user_id'] == _myId),
              'used_by_me': e.value.any((r) => r['user_id'] == _myId),
              'recent_sender_ids': [
                for (final r in e.value.take(3))
                  if ((r['user_id'] ?? '').isNotEmpty) _sender(r['user_id']!),
              ],
            },
        ],
        'are_tags': false,
        'paid_reactors': const <Object>[],
        'can_get_added_reactions': true,
      },
    };
  }

  Map<String, dynamic>? _photoSizeThumbnail(String mediaId) {
    if (mediaId.isEmpty) return null;
    final dims = _mediaDims[mediaId];
    return {
      '@type': 'thumbnail',
      'format': {'@type': 'thumbnailFormatJpeg'},
      'width': dims?[0] ?? 320,
      'height': dims?[1] ?? 180,
      'file': _fileForMedia(mediaId, kind: 'image'),
    };
  }

  Map<String, dynamic> _videoContent(Map<String, dynamic> m, Map<String, dynamic> meta, String mediaId, Map<String, dynamic> caption) {
    final thumbId = meta['thumbnail_id']?.toString() ?? '';
    return {
      '@type': 'messageVideo',
      'video': {
        '@type': 'video',
        'duration': _durationSec(meta),
        'width': QlTdEngine._int(meta['width']) ?? 0,
        'height': QlTdEngine._int(meta['height']) ?? 0,
        'file_name': (meta['file_name']?.toString().isNotEmpty == true)
            ? meta['file_name']
            : 'video.mp4',
        'mime_type': meta['mime']?.toString() ?? 'video/mp4',
        'has_stickers': false,
        'supports_streaming': true,
        'minithumbnail': null,
        'thumbnail': _photoSizeThumbnail(thumbId),
        'video': _fileForMedia(mediaId, kind: 'video', size: QlTdEngine._int(meta['bytes']) ?? 0, fileName: meta['file_name']?.toString() ?? ''),
      },
      'alternative_videos': const <Object>[],
      'caption': caption,
      'show_caption_above_media': false,
      'has_spoiler': false,
      'is_secret': false,
    };
  }

  Future<void> _refreshBlocks() async {
    try {
      final result = await _apiOrThrow.get('/me/blocks');
      _blockedUserIds
        ..clear()
        ..addAll([
          for (final u in (result['user_ids'] as List? ?? const []))
            if (u.toString().isNotEmpty) u.toString(),
        ]);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _setSenderBlockList(Map<String, dynamic> r) async {
    final sender = r['sender_id'];
    if (sender is! Map || sender['@type'] != 'messageSenderUser') {
      return _unsupported('setMessageSenderBlockList(${sender is Map ? sender['@type'] : 'null'})');
    }
    final uid = _userIdByInt[QlTdEngine._int(sender['user_id']) ?? 0];
    if (uid == null) return _error(404, 'User not found');
    final list = r['block_list'];
    final blocked = list is Map && list['@type'] == 'blockListMain';
    await _apiOrThrow.put('/users/$uid/block', {'blocked': blocked});
    if (blocked) {
      _blockedUserIds.add(uid);
    } else {
      _blockedUserIds.remove(uid);
    }
    final userInt = qlUserInt(uid);
    _emit({
      '@type': 'updateMessageSenderBlockList',
      'sender_id': {'@type': 'messageSenderUser', 'user_id': userInt},
      'block_list': blocked ? {'@type': 'blockListMain'} : null,
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _blockedSenders(Map<String, dynamic> r) async {
    await _refreshBlocks();
    final offset = QlTdEngine._int(r['offset']) ?? 0;
    final limit = (QlTdEngine._int(r['limit']) ?? 100).clamp(1, 200);
    final all = _blockedUserIds.toList();
    final slice = all.skip(offset).take(limit).toList();
    for (final id in slice) {
      await _ensureUser(id);
    }
    return {
      '@type': 'messageSenders',
      'total_count': all.length,
      'senders': [
        for (final id in slice) {'@type': 'messageSenderUser', 'user_id': qlUserInt(id)},
      ],
    };
  }

  Future<Map<String, dynamic>> _deleteChatHistory(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) {
      c.messages.clear();
      c.lastMessage = null;
      if (r['remove_from_chat_list'] == true && c.announced) {
        _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c, removed: true)});
      }
      return _ok;
    }
    final revoke = r['revoke'] == true;
    await _apiOrThrow.post('/conversations/${c.id}/clear', {'both': revoke});
    _applyCleared(c, throughSeq: c.lastSeq);
    if (r['remove_from_chat_list'] == true && c.announced) {
      _emit({'@type': 'updateChatPosition', 'chat_id': c.chatId, 'position': _position(c, removed: true)});
    }
    return _ok;
  }

  void _applyCleared(_Conv c, {required int throughSeq}) {
    final removed = <int>[
      for (final seq in c.messages.keys)
        if (seq <= throughSeq) seq,
    ];
    _removeMessages(c, removed);
    c.pinnedSeqs.removeWhere((s) => s <= throughSeq);
    c.reactionsBySeq.removeWhere((s, _) => s <= throughSeq);
    if (c.lastMessage != null && qlSeqOf(c.lastMessage!['id'] as int) <= throughSeq) {
      c.lastMessage = null;
      if (c.announced) {
        _emit({'@type': 'updateChatLastMessage', 'chat_id': c.chatId, 'last_message': null, 'positions': [_position(c)]});
      }
    }
  }

  Future<Map<String, dynamic>> _reportChat(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final option = r['option_id']?.toString() ?? '';
    if (option.isEmpty) {
      return {
        '@type': 'reportChatResultOptionRequired',
        'title': '请选择举报原因',
        'options': [
          for (final o in _reportOptions)
            {'@type': 'reportOption', 'id': o.$1, 'text': o.$2},
        ],
      };
    }
    final label = {
      for (final o in _reportOptions) o.$1: o.$2,
    }[option] ?? option;
    final text = (r['text']?.toString() ?? '').trim();
    final ids = r['message_ids'] as List? ?? const [];
    String messageId = '';
    if (ids.isNotEmpty) {
      final mid = QlTdEngine._int(ids.first) ?? 0;
      messageId = c.messages[qlSeqOf(mid)]?['@ql_id']?.toString() ?? '';
    }
    await _apiOrThrow.post('/conversations/${c.id}/report', {
      'message_id': messageId,
      'reason': text.isEmpty ? label : '$label: $text',
    });
    return {'@type': 'reportChatResultOk'};
  }

  Future<Map<String, dynamic>> _doSetChatTitle(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final title = (r['title']?.toString() ?? '').trim();
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    if (title.isEmpty) return _error(400, 'TITLE_EMPTY');
    await _apiOrThrow.patch('/conversations/${c.id}', {'title': title});
    c.title = title;
    if (c.announced) {
      _emit({'@type': 'updateChatTitle', 'chat_id': c.chatId, 'title': title});
      if (c.isChannel) {
        _emit({'@type': 'updateSupergroup', 'supergroup': _supergroup(c)});
      } else {
        _emit({'@type': 'updateBasicGroup', 'basic_group': _basicGroup(c)});
      }
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _setChatPhoto(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    final photo = r['photo'];
    String mediaId = '';
    if (photo == null) {
      mediaId = '';
    } else if (photo is Map && photo['@type'] == 'inputChatPhotoStatic') {
      final path = _inputFilePath(photo['photo']);
      if (path == null) return _error(400, 'PHOTO_INVALID');
      final uploaded = await _apiOrThrow.uploadFile(path);
      mediaId = uploaded['id']?.toString() ?? '';
      if (mediaId.isEmpty) return _error(500, 'upload_failed');
      final size = qlImageSizeOfFile(path);
      if (size != null) _mediaDims[mediaId] = [size.$1, size.$2];
    } else {
      return _unsupported('setChatPhoto(${photo is Map ? photo['@type'] : 'null'})');
    }
    await _apiOrThrow.patch('/conversations/${c.id}', {'avatar_media_id': mediaId});
    c.avatarMediaId = mediaId;
    if (c.announced) {
      _emit({
        '@type': 'updateChatPhoto',
        'chat_id': c.chatId,
        'photo': mediaId.isEmpty ? null : _chatPhotoInfo(mediaId),
      });
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _createSupergroup(Map<String, dynamic> r) async {
    final title = (r['title']?.toString() ?? '').trim();
    if (title.isEmpty) return _error(400, '请输入名称');
    final isChannel = r['is_channel'] == true;
    if (!isChannel) return _createGroup(r);
    final result = await _apiOrThrow.post('/conversations', {
      'kind': 'channel',
      'title': title,
      'member_ids': const <String>[],
    });
    final id = result['id']?.toString() ?? '';
    final c = await _discoverConversation(id);
    if (c == null) return _error(500, 'Channel was created but could not be loaded');
    return _tdChat(c);
  }

  Map<String, dynamic> _supergroup(_Conv c) {
    return {
      '@type': 'supergroup',
      'id': qlGroupInt(c.id),
      'usernames': null,
      'date': 0,
      'status': _memberStatus(c.role),
      'member_count': c.members.length,
      'boost_level': 0,
      'has_automatic_translation_enabled': false,
      'has_linked_chat': false,
      'has_location': false,
      'has_posted_to_profile_stories': false,
      'sign_messages': false,
      'show_message_sender': false,
      'join_to_send_messages': false,
      'join_by_request': false,
      'is_slow_mode_enabled': false,
      'is_channel': c.isChannel,
      'is_broadcast_group': c.isChannel,
      'is_forum': false,
      'is_direct_messages_group': false,
      'is_administered_direct_messages_group': false,
      'has_direct_messages_group': false,
      'has_forum_tabs': false,
      'is_verified': false,
      'has_sensitive_content': false,
      'restriction_info': null,
      'paid_message_star_count': 0,
      'has_active_stories': false,
      'has_unread_active_stories': false,
    };
  }

  Map<String, dynamic> _supergroupById(int id) {
    for (final c in _convs.values) {
      if (c.isChannel && qlGroupInt(c.id) == id) return _supergroup(c);
    }
    return _error(404, 'Supergroup not found');
  }

  Future<Map<String, dynamic>> _supergroupFullInfo(int id) async {
    _Conv? found;
    for (final c in _convs.values) {
      if (c.isChannel && qlGroupInt(c.id) == id) found = c;
    }
    if (found == null) return _error(404, 'Supergroup not found');
    if (!found.membersLoaded) {
      try {
        await _loadMembers(found);
      } catch (_) {}
    }
    return {
      '@type': 'supergroupFullInfo',
      'photo': found.avatarMediaId.isEmpty ? null : _chatPhoto(found.avatarMediaId),
      'description': '',
      'member_count': found.members.length,
      'administrator_count': found.members.where((m) {
        final role = m['role']?.toString() ?? '';
        return role == 'owner' || role == 'admin';
      }).length,
      'restricted_count': 0,
      'banned_count': 0,
      'linked_chat_id': 0,
      'slow_mode_delay': 0,
      'slow_mode_delay_expires_in': 0.0,
      'can_enable_paid_messages': false,
      'can_enable_paid_reaction': false,
      'can_get_members': true,
      'has_hidden_members': false,
      'can_hide_members': false,
      'can_set_sticker_set': false,
      'can_set_location': false,
      'can_get_statistics': false,
      'can_get_revenue_statistics': false,
      'can_get_star_revenue_statistics': false,
      'can_send_gift': false,
      'can_toggle_aggressive_anti_spam': false,
      'is_all_history_available': true,
      'can_have_sponsored_messages': false,
      'has_aggressive_anti_spam_enabled': false,
      'has_paid_media_allowed': false,
      'has_pinned_stories': false,
      'gift_count': 0,
      'my_boost_count': 0,
      'unrestrict_boost_count': 0,
      'sticker_set_id': 0,
      'custom_emoji_sticker_set_id': 0,
      'location': null,
      'invite_link': null,
      'bot_verification': null,
      'main_profile_tab': null,
      'upgraded_from_basic_group_id': 0,
      'upgraded_from_max_message_id': 0,
    };
  }

  Future<Map<String, dynamic>> _searchChatMessages(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) return _searchChatMessagesLocal(r);
    final filter = (r['filter'] as Map?)?['@type']?.toString() ?? 'searchMessagesFilterEmpty';
    final q = (r['query']?.toString() ?? '').trim();
    final from = QlTdEngine._int(r['from_message_id']) ?? 0;
    final before = from == 0 ? 0 : qlSeqOf(from);
    final limit = (QlTdEngine._int(r['limit']) ?? 50).clamp(1, 100);
    final kind = switch (filter) {
      'searchMessagesFilterEmpty' || 'searchMessagesFilterMention' || 'searchMessagesFilterUnreadMention' => '',
      'searchMessagesFilterPhoto' => 'image',
      'searchMessagesFilterVideo' => 'video',
      'searchMessagesFilterPhotoAndVideo' => 'all',
      'searchMessagesFilterDocument' => 'file',
      'searchMessagesFilterVoiceNote' || 'searchMessagesFilterVoiceAndVideoNote' => 'voice',
      'searchMessagesFilterUrl' => 'link',
      'searchMessagesFilterAnimation' ||
      'searchMessagesFilterAudio' ||
      'searchMessagesFilterVideoNote' ||
      'searchMessagesFilterPoll' ||
      'searchMessagesFilterChatPhoto' ||
      'searchMessagesFilterPinned' =>
        'unsupported-empty',
      _ => 'unsupported-empty',
    };
    if (filter == 'searchMessagesFilterPinned') {
      return _pinnedMessages(c, before: before, limit: limit);
    }
    if (kind == 'unsupported-empty' && q.isEmpty) {
      return {
        '@type': 'foundChatMessages',
        'total_count': 0,
        'messages': const <Object>[],
        'next_from_message_id': 0,
      };
    }
    try {
      if (q.isNotEmpty && (kind.isEmpty || kind == 'unsupported-empty')) {
        final result = await _apiOrThrow.get('/conversations/${c.id}/search', {
          'q': q,
          if (before > 0) 'before': '$before',
          'limit': '$limit',
        });
        return _foundFromRaw(c, result['messages'], limit);
      }
      if (kind.isEmpty && q.isEmpty) {
        return _unsupported('searchChatMessages(empty)');
      }
      final query = <String, String>{
        if (kind.isNotEmpty && kind != 'unsupported-empty') 'kind': kind == 'all' ? 'all' : kind,
        if (before > 0) 'before': '$before',
        'limit': '$limit',
      };
      final result = await _apiOrThrow.get('/conversations/${c.id}/media', query);
      final found = _foundFromRaw(c, result['messages'], limit);
      final counts = result['counts'];
      if (counts is Map) {
        found['total_count'] = switch (kind) {
          'image' => QlTdEngine._int(counts['image']) ?? found['total_count'],
          'video' => QlTdEngine._int(counts['video']) ?? found['total_count'],
          'file' => QlTdEngine._int(counts['file']) ?? found['total_count'],
          'voice' => QlTdEngine._int(counts['voice']) ?? found['total_count'],
          'link' => QlTdEngine._int(counts['link']) ?? found['total_count'],
          _ => (QlTdEngine._int(counts['image']) ?? 0) +
              (QlTdEngine._int(counts['video']) ?? 0) +
              (found['total_count'] as int? ?? 0),
        };
      }
      return found;
    } on QlApiException catch (e) {
      if (e.statusCode == 400 && q.isNotEmpty) {
        // Empty / untokenizable query: not an engine failure.
        return {
          '@type': 'foundChatMessages',
          'total_count': 0,
          'messages': const <Object>[],
          'next_from_message_id': 0,
        };
      }
      rethrow;
    }
  }

  Map<String, dynamic> _foundFromRaw(_Conv c, Object? list, int limit) {
    final out = <Map<String, dynamic>>[];
    if (list is List) {
      for (final raw in list) {
        if (raw is! Map) continue;
        final td = _tdMessage(c, Map<String, dynamic>.from(raw));
        if (td == null) continue;
        _cacheMessage(c, td, Map<String, dynamic>.from(raw));
        out.add(td);
      }
    }
    return {
      '@type': 'foundChatMessages',
      'total_count': out.length,
      'messages': out,
      'next_from_message_id': out.length >= limit && out.isNotEmpty ? out.last['id'] : 0,
    };
  }

  Future<Map<String, dynamic>> _pinnedMessages(_Conv c, {required int before, required int limit}) async {
    final result = await _apiOrThrow.get('/conversations/${c.id}/pins');
    final out = <Map<String, dynamic>>[];
    if (result['messages'] is List) {
      for (final raw in result['messages'] as List) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final td = _tdMessage(c, m);
        if (td == null) continue;
        final seq = qlSeqOf(td['id'] as int);
        c.pinnedSeqs.add(seq);
        td['is_pinned'] = true;
        _cacheMessage(c, td, m);
        if (before > 0 && seq >= before) continue;
        out.add(td);
        if (out.length >= limit) break;
      }
    }
    return {
      '@type': 'foundChatMessages',
      'total_count': c.pinnedSeqs.length,
      'messages': out,
      'next_from_message_id': out.length >= limit && out.isNotEmpty ? out.last['id'] : 0,
    };
  }

  Future<Map<String, dynamic>> _messageCount(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) {
      return {'@type': 'count', 'count': 0};
    }
    final filter = (r['filter'] as Map?)?['@type']?.toString() ?? '';
    if (filter == 'searchMessagesFilterPinned') {
      final result = await _apiOrThrow.get('/conversations/${c.id}/pins');
      final n = (result['messages'] as List?)?.length ?? 0;
      return {'@type': 'count', 'count': n};
    }
    final kind = switch (filter) {
      'searchMessagesFilterPhoto' => 'image',
      'searchMessagesFilterVideo' => 'video',
      'searchMessagesFilterDocument' => 'file',
      'searchMessagesFilterVoiceNote' || 'searchMessagesFilterVoiceAndVideoNote' => 'voice',
      'searchMessagesFilterUrl' => 'link',
      'searchMessagesFilterPhotoAndVideo' => 'all',
      _ => 'all',
    };
    final result = await _apiOrThrow.get('/conversations/${c.id}/media', {
      'kind': kind,
      'limit': '1',
    });
    final counts = result['counts'];
    var n = 0;
    if (counts is Map) {
      n = switch (kind) {
        'image' => QlTdEngine._int(counts['image']) ?? 0,
        'video' => QlTdEngine._int(counts['video']) ?? 0,
        'file' => QlTdEngine._int(counts['file']) ?? 0,
        'voice' => QlTdEngine._int(counts['voice']) ?? 0,
        'link' => QlTdEngine._int(counts['link']) ?? 0,
        _ => (QlTdEngine._int(counts['image']) ?? 0) +
            (QlTdEngine._int(counts['video']) ?? 0) +
            (QlTdEngine._int(counts['file']) ?? 0) +
            (QlTdEngine._int(counts['voice']) ?? 0),
      };
    }
    return {'@type': 'count', 'count': n};
  }

  Future<Map<String, dynamic>> _searchMessages(Map<String, dynamic> r) async {
    final q = (r['query']?.toString() ?? '').trim();
    if (q.isEmpty) {
      return {
        '@type': 'foundMessages',
        'total_count': 0,
        'messages': const <Object>[],
        'next_offset': '',
      };
    }
    final limit = (QlTdEngine._int(r['limit']) ?? 20).clamp(1, 50);
    final out = <Map<String, dynamic>>[];
    for (final c in _convs.values) {
      if (!c.announced || c.id.startsWith('virtual:')) continue;
      try {
        final result = await _apiOrThrow.get('/conversations/${c.id}/search', {
          'q': q,
          'limit': '10',
        });
        final found = _foundFromRaw(c, result['messages'], 10);
        out.addAll((found['messages'] as List).cast<Map<String, dynamic>>());
      } catch (_) {}
      if (out.length >= limit) break;
    }
    return {
      '@type': 'foundMessages',
      'total_count': out.length,
      'messages': out.take(limit).toList(),
      'next_offset': '',
    };
  }

  Future<Map<String, dynamic>> _forwardMessages(Map<String, dynamic> r) async {
    final dest = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final src = _conv(QlTdEngine._int(r['from_chat_id']) ?? 0);
    if (dest == null || src == null) return _error(400, 'Chat not found');
    if (dest.id.startsWith('virtual:')) {
      return _error(400, 'Chat not found');
    }
    final out = <Map<String, dynamic>>[];
    for (final v in (r['message_ids'] as List? ?? const [])) {
      final id = QlTdEngine._int(v) ?? 0;
      final backendId = src.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
      if (backendId.isEmpty) continue;
      final clientId = 'fwd-${DateTime.now().microsecondsSinceEpoch}-${id.toRadixString(16)}';
      final sent = await _apiOrThrow.post('/messages/$backendId/forward', {
        'conversation_id': dest.id,
        'client_msg_id': clientId,
      });
      final td = _tdMessage(dest, sent);
      if (td == null) continue;
      _cacheMessage(dest, td, sent);
      _emit({'@type': 'updateNewMessage', 'message': td});
      _advanceLast(dest, td, incoming: false);
      out.add(td);
    }
    return {'@type': 'messages', 'total_count': out.length, 'messages': out};
  }

  Future<Map<String, dynamic>> _pinMessage(Map<String, dynamic> r, {required bool remove}) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final backendId = c.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
    if (backendId.isEmpty) return _error(400, 'Message not found');
    await _apiOrThrow.put('/conversations/${c.id}/pins', {
      'message_id': backendId,
      'remove': remove,
    });
    final seq = qlSeqOf(id);
    if (remove) {
      c.pinnedSeqs.remove(seq);
    } else {
      c.pinnedSeqs.add(seq);
    }
    final cached = c.messages[seq];
    if (cached != null) cached['is_pinned'] = !remove;
    _emit({
      '@type': 'updateMessageIsPinned',
      'chat_id': c.chatId,
      'message_id': id,
      'is_pinned': !remove,
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _unpinAll(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final result = await _apiOrThrow.get('/conversations/${c.id}/pins');
    if (result['messages'] is List) {
      for (final raw in result['messages'] as List) {
        if (raw is! Map) continue;
        final mid = raw['id']?.toString() ?? '';
        if (mid.isEmpty) continue;
        await _apiOrThrow.put('/conversations/${c.id}/pins', {
          'message_id': mid,
          'remove': true,
        });
        final seq = QlTdEngine._int(raw['conversation_seq']) ?? 0;
        c.pinnedSeqs.remove(seq);
        c.messages[seq]?['is_pinned'] = false;
        if (seq > 0) {
          _emit({
            '@type': 'updateMessageIsPinned',
            'chat_id': c.chatId,
            'message_id': qlMessageId(seq),
            'is_pinned': false,
          });
        }
      }
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _setReaction(Map<String, dynamic> r, {required bool remove}) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final backendId = c.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
    if (backendId.isEmpty) return _error(400, 'Message not found');
    final type = r['reaction_type'] ?? r['reaction'];
    final emoji = type is Map ? type['emoji']?.toString() ?? '' : '';
    if (emoji.isEmpty) return _error(400, 'REACTION_INVALID');
    await _apiOrThrow.put('/messages/$backendId/reactions', {
      'emoji': emoji,
      'remove': remove,
    });
    _applyReaction(c, qlSeqOf(id), _myId, emoji, remove);
    return _ok;
  }

  void _applyReaction(_Conv c, int seq, String userId, String emoji, bool remove) {
    final list = c.reactionsBySeq.putIfAbsent(seq, () => []);
    list.removeWhere((r) => r['user_id'] == userId && r['emoji'] == emoji);
    if (!remove) list.add({'user_id': userId, 'emoji': emoji});
    final cached = c.messages[seq];
    if (cached != null) {
      cached['interaction_info'] = _interactionInfo(c, seq);
      if (c.announced) {
        _emit({
          '@type': 'updateMessageInteractionInfo',
          'chat_id': c.chatId,
          'message_id': qlMessageId(seq),
          'interaction_info': cached['interaction_info'],
        });
      }
    }
  }

  Map<String, dynamic> _availableReactions() {
    final items = [
      for (final e in _reactionEmojis)
        {
          '@type': 'availableReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': e},
          'needs_premium': false,
        },
    ];
    return {
      '@type': 'availableReactions',
      'top_reactions': items,
      'recent_reactions': const <Object>[],
      'popular_reactions': items,
      'allow_custom_emoji': false,
      'reactions_are_tags': false,
      'unavailability_reason': null,
    };
  }

  Future<Map<String, dynamic>> _addedReactions(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final backendId = c.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
    if (backendId.isEmpty) return _error(400, 'Message not found');
    final result = await _apiOrThrow.get('/messages/$backendId/reactions');
    final wanted = (r['reaction_type'] as Map?)?['emoji']?.toString();
    final added = <Map<String, dynamic>>[];
    if (result['reactions'] is List) {
      final seq = qlSeqOf(id);
      c.reactionsBySeq[seq] = [];
      for (final raw in result['reactions'] as List) {
        if (raw is! Map) continue;
        final uid = raw['user_id']?.toString() ?? '';
        final emoji = raw['emoji']?.toString() ?? '';
        if (uid.isEmpty || emoji.isEmpty) continue;
        c.reactionsBySeq[seq]!.add({'user_id': uid, 'emoji': emoji});
        if (wanted != null && wanted.isNotEmpty && emoji != wanted) continue;
        added.add({
          '@type': 'addedReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
          'sender_id': _sender(uid),
          'is_outgoing': uid == _myId,
        });
      }
      final cached = c.messages[seq];
      if (cached != null) cached['interaction_info'] = _interactionInfo(c, seq);
    }
    return {
      '@type': 'addedReactions',
      'total_count': added.length,
      'reactions': added,
      'next_offset': '',
    };
  }

  void _onReactionUpdated(String cid, Map<String, dynamic> data) {
    final c = _convs[cid];
    if (c == null) return;
    final mid = data['message_id']?.toString() ?? '';
    final ref = _messageRef[mid];
    final seq = ref?.$2;
    if (seq == null) return;
    _applyReaction(
      c,
      seq,
      data['user_id']?.toString() ?? '',
      data['emoji']?.toString() ?? '',
      data['removed'] == true,
    );
  }

  void _onPinned(String cid, Map<String, dynamic> data, {required bool remove}) {
    final c = _convs[cid];
    if (c == null) return;
    final mid = data['message_id']?.toString() ?? '';
    final ref = _messageRef[mid];
    final seq = ref?.$2;
    if (seq == null) return;
    if (remove) {
      c.pinnedSeqs.remove(seq);
    } else {
      c.pinnedSeqs.add(seq);
    }
    c.messages[seq]?['is_pinned'] = !remove;
    if (c.announced) {
      _emit({
        '@type': 'updateMessageIsPinned',
        'chat_id': c.chatId,
        'message_id': qlMessageId(seq),
        'is_pinned': !remove,
      });
    }
  }

  Future<Map<String, String>> _uploadHeadersFor(String kind, String path, Map? content) async {
    final headers = <String, String>{};
    final name = path.split(Platform.pathSeparator).last;
    if (name.isNotEmpty) headers['X-Media-Filename'] = name;
    if (kind == 'image' || kind == 'video') {
      final size = qlImageSizeOfFile(path);
      if (size != null) {
        headers['X-Media-Width'] = '${size.$1}';
        headers['X-Media-Height'] = '${size.$2}';
      }
    }
    if (content is Map) {
      if (kind == 'voice') {
        final note = content['voice_note'];
        if (note is Map) {
          final dur = QlTdEngine._int(note['duration']) ?? 0;
          if (dur > 0) headers['X-Media-Duration-Ms'] = '${dur * 1000}';
          final wave = note['waveform']?.toString() ?? '';
          if (wave.isNotEmpty) headers['X-Media-Waveform'] = wave;
        }
      }
      if (kind == 'video') {
        final video = content['video'];
        if (video is Map) {
          final dur = QlTdEngine._int(video['duration']) ?? 0;
          if (dur > 0) headers['X-Media-Duration-Ms'] = '${dur * 1000}';
          final w = QlTdEngine._int(video['width']);
          final h = QlTdEngine._int(video['height']);
          if (w != null && w > 0) headers['X-Media-Width'] = '$w';
          if (h != null && h > 0) headers['X-Media-Height'] = '$h';
        }
      }
    }
    return headers;
  }
}
