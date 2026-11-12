part of 'ql_engine.dart';

// MARK: - Stable id mapping (backend string ids -> TDLib integer ids)

int _fnv1a64(String s) {
  // FNV-1a over UTF-8, truncated arithmetic kept within 64-bit ints.
  var hash = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    hash ^= b;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}

/// Positive user id < 2^40 (JS-safe, below TDLib's supergroup range).
int qlUserInt(String id) {
  if (id.isEmpty) return 0;
  final v = _fnv1a64('u:$id') & 0xFFFFFFFFFF;
  return v == 0 ? 1 : v;
}

/// Basic-group id in [1, 999999999999]; the chat id is its negation.
int qlGroupInt(String convId) =>
    (_fnv1a64('g:$convId') & 0x7FFFFFFFFFFF) % 999999999998 + 1;

int qlMediaFileId(String mediaId) =>
    (_fnv1a64('f:$mediaId') & 0x3FFFFFFF) | 0x40000000;

int qlMessageId(int seq) => seq << 20;
int qlSeqOf(int messageId) => messageId >> 20;

int _parseDate(Object? v) {
  if (v is String && v.isNotEmpty) {
    final d = DateTime.tryParse(v);
    if (d != null) return d.millisecondsSinceEpoch ~/ 1000;
  }
  return 0;
}

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _formatted(String text, [List<Object?>? entities]) => {
  '@type': 'formattedText',
  'text': text,
  'entities': entities ?? const <Object>[],
};

final RegExp _urlPattern = RegExp(
  r'''(?:https?://|www\.)[^\s<>"'，。！？、]+''',
  caseSensitive: false,
);
final RegExp _mentionPattern = RegExp(r'(?<![\w@])@[A-Za-z0-9_]{3,32}');
final RegExp _hashtagPattern = RegExp(r'(?<![\w#])#[\p{L}\p{N}_]{1,64}', unicode: true);

List<Map<String, dynamic>> _detectEntities(String text) {
  final out = <Map<String, dynamic>>[];
  void add(RegExp re, String type) {
    for (final m in re.allMatches(text)) {
      var end = m.end;
      // Trim trailing punctuation a sentence would usually own.
      while (end > m.start && '.,;:!?)]}'.contains(text[end - 1])) {
        end--;
      }
      if (end <= m.start) continue;
      final overlaps = out.any(
        (e) => m.start < (e['offset'] as int) + (e['length'] as int) &&
            (e['offset'] as int) < end,
      );
      if (overlaps) continue;
      out.add({
        '@type': 'textEntity',
        'offset': m.start,
        'length': end - m.start,
        'type': {'@type': type},
      });
    }
  }

  add(_urlPattern, 'textEntityTypeUrl');
  add(_mentionPattern, 'textEntityTypeMention');
  add(_hashtagPattern, 'textEntityTypeHashtag');
  out.sort((a, b) => (a['offset'] as int).compareTo(b['offset'] as int));
  return out;
}

extension on QlTdEngine {
  // MARK: Entities

  List<Map<String, dynamic>> _tdEntities(String text, Object? raw) {
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final offset = QlTdEngine._int(e['offset']) ?? 0;
        final length = QlTdEngine._int(e['length']) ?? 0;
        final Map<String, dynamic>? type = switch (e['type']) {
          'bold' => {'@type': 'textEntityTypeBold'},
          'italic' => {'@type': 'textEntityTypeItalic'},
          'underline' => {'@type': 'textEntityTypeUnderline'},
          'strikethrough' => {'@type': 'textEntityTypeStrikethrough'},
          'code' => {'@type': 'textEntityTypeCode'},
          'pre' => (e['language']?.toString() ?? '').isEmpty
              ? {'@type': 'textEntityTypePre'}
              : {'@type': 'textEntityTypePreCode', 'language': e['language']},
          'blockquote' => {'@type': 'textEntityTypeBlockQuote'},
          'spoiler' => {'@type': 'textEntityTypeSpoiler'},
          'text_link' => {'@type': 'textEntityTypeTextUrl', 'url': e['url'] ?? ''},
          'url' => {'@type': 'textEntityTypeUrl'},
          'mention' => {'@type': 'textEntityTypeMention'},
          'hashtag' => {'@type': 'textEntityTypeHashtag'},
          _ => null,
        };
        if (type == null || length <= 0) continue;
        out.add({
          '@type': 'textEntity',
          'offset': offset,
          'length': length,
          'type': type,
        });
      }
    }
    // Auto-detect links/mentions/hashtags the sender did not mark up, the
    // way Telegram's server does, without overlapping explicit entities.
    for (final d in _detectEntities(text)) {
      final s = d['offset'] as int;
      final t = s + (d['length'] as int);
      final overlaps = out.any((e) {
        final es = e['offset'] as int;
        final et = es + (e['length'] as int);
        return s < et && es < t;
      });
      if (!overlaps) out.add(d);
    }
    out.sort((a, b) => (a['offset'] as int).compareTo(b['offset'] as int));
    return out;
  }

  /// TDLib formattedText -> backend entities (formatting only; links,
  /// mentions and hashtags are re-detected on display).
  List<Map<String, dynamic>> _backendEntities(Map<String, dynamic>? text) {
    final out = <Map<String, dynamic>>[];
    final raw = text?['entities'];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map) continue;
      final type = e['type'];
      if (type is! Map) continue;
      final offset = QlTdEngine._int(e['offset']) ?? 0;
      final length = QlTdEngine._int(e['length']) ?? 0;
      if (length <= 0) continue;
      final Map<String, dynamic>? mapped = switch (type['@type']) {
        'textEntityTypeBold' => {'type': 'bold'},
        'textEntityTypeItalic' => {'type': 'italic'},
        'textEntityTypeUnderline' => {'type': 'underline'},
        'textEntityTypeStrikethrough' => {'type': 'strikethrough'},
        'textEntityTypeCode' => {'type': 'code'},
        'textEntityTypePre' => {'type': 'pre'},
        'textEntityTypePreCode' => {
          'type': 'pre',
          if ((type['language']?.toString() ?? '').isNotEmpty)
            'language': type['language'].toString().substring(
              0,
              math.min(32, type['language'].toString().length),
            ),
        },
        'textEntityTypeBlockQuote' ||
        'textEntityTypeExpandableBlockQuote' => {'type': 'blockquote'},
        'textEntityTypeSpoiler' => {'type': 'spoiler'},
        'textEntityTypeTextUrl' => {'type': 'text_link', 'url': type['url'] ?? ''},
        _ => null,
      };
      if (mapped == null) continue;
      out.add({...mapped, 'offset': offset, 'length': length});
    }
    // The backend rejects crossing ranges; drop anything that would cross.
    out.sort((a, b) => (a['offset'] as int).compareTo(b['offset'] as int));
    final accepted = <Map<String, dynamic>>[];
    for (final e in out) {
      final s = e['offset'] as int;
      final t = s + (e['length'] as int);
      final bad = accepted.any((x) {
        final xs = x['offset'] as int;
        final xt = xs + (x['length'] as int);
        final crosses = s < xt && xs < t && !(xs <= s && t <= xt) && !(s <= xs && xt <= t);
        final codeOverlap = (s < xt && xs < t) &&
            (e['type'] == 'code' || e['type'] == 'pre' || x['type'] == 'code' || x['type'] == 'pre');
        final sameType = x['type'] == e['type'] && s < xt && xs < t;
        return crosses || codeOverlap || sameType;
      });
      if (!bad) accepted.add(e);
    }
    return accepted.take(128).toList();
  }

  // MARK: Users

  String _displayName(Map<String, dynamic>? raw) {
    if (raw == null) return '';
    final name = raw['display_name']?.toString() ?? '';
    if (name.trim().isNotEmpty) return name.trim();
    return raw['handle']?.toString() ?? '';
  }

  Map<String, dynamic> _userStatus(Map<String, dynamic>? raw) {
    if (raw == null) return {'@type': 'userStatusEmpty'};
    if (raw['online'] == true) {
      return {'@type': 'userStatusOnline', 'expires': _nowSeconds() + 300};
    }
    final seen = _parseDate(raw['last_seen']);
    if (seen == 0) return {'@type': 'userStatusEmpty'};
    return {'@type': 'userStatusOffline', 'was_online': seen};
  }

  Map<String, dynamic>? _profilePhoto(String avatarMediaId) {
    if (avatarMediaId.isEmpty) return null;
    final file = _fileForMedia(avatarMediaId, kind: 'avatar');
    return {
      '@type': 'profilePhoto',
      'id': qlMediaFileId(avatarMediaId),
      'small': file,
      'big': file,
      'minithumbnail': null,
      'has_animation': false,
      'is_personal': false,
    };
  }

  Map<String, dynamic>? _chatPhotoInfo(String avatarMediaId) {
    if (avatarMediaId.isEmpty) return null;
    final file = _fileForMedia(avatarMediaId, kind: 'avatar');
    return {
      '@type': 'chatPhotoInfo',
      'small': file,
      'big': file,
      'minithumbnail': null,
      'has_animation': false,
      'is_personal': false,
    };
  }

  Map<String, dynamic> _tdUser(String id) {
    final raw = _users[id];
    final handle = raw?['handle']?.toString() ?? '';
    final name = _displayName(raw);
    final isMe = id == _myId;
    return {
      '@type': 'user',
      'id': qlUserInt(id),
      'first_name': name.isEmpty ? (handle.isEmpty ? '轻聊用户' : handle) : name,
      'last_name': '',
      'usernames': {
        '@type': 'usernames',
        'active_usernames': [if (handle.isNotEmpty) handle],
        'disabled_usernames': const <String>[],
        'editable_username': isMe ? handle : '',
        'collectible_usernames': const <String>[],
      },
      'phone_number': '',
      'status': isMe
          ? {'@type': 'userStatusOnline', 'expires': _nowSeconds() + 300}
          : _userStatus(raw),
      'profile_photo': _profilePhoto(raw?['avatar_media_id']?.toString() ?? ''),
      'accent_color_id': qlUserInt(id) % 7,
      'background_custom_emoji_id': 0,
      'profile_accent_color_id': -1,
      'profile_background_custom_emoji_id': 0,
      'emoji_status': null,
      'is_contact': !isMe,
      'is_mutual_contact': !isMe,
      'is_close_friend': false,
      'verification_status': null,
      'is_premium': false,
      'is_support': false,
      'restriction_info': null,
      'has_active_stories': false,
      'has_unread_active_stories': false,
      'restricts_new_chats': false,
      'paid_message_star_count': 0,
      'have_access': true,
      'type': {'@type': 'userTypeRegular'},
      'language_code': '',
      'added_to_attachment_menu': false,
    };
  }

  void _rememberUser(Map<String, dynamic> raw, {bool emit = true}) {
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final previous = _users[id];
    final merged = <String, dynamic>{...?previous, ...raw};
    _users[id] = merged;
    _userIdByInt[qlUserInt(id)] = id;
    if (emit) {
      final changed = previous == null ||
          previous['display_name'] != merged['display_name'] ||
          previous['avatar_media_id'] != merged['avatar_media_id'] ||
          previous['handle'] != merged['handle'];
      if (changed) {
        _emit({'@type': 'updateUser', 'user': _tdUser(id)});
        _schedulePersist();
        // Direct chats mirror the peer's name and avatar.
        for (final c in _convs.values) {
          if (c.announced && !c.isGroup && c.peerId == id) {
            _emit({'@type': 'updateChatTitle', 'chat_id': c.chatId, 'title': _chatTitle(c)});
            _emit({
              '@type': 'updateChatPhoto',
              'chat_id': c.chatId,
              'photo': _chatPhotoInfo(merged['avatar_media_id']?.toString() ?? ''),
            });
          }
        }
      }
    }
  }

  Future<String?> _ensureUser(String id) async {
    if (id.isEmpty) return null;
    if (_users.containsKey(id) && _users[id]!['handle'] != null &&
        _users[id]!.containsKey('online')) {
      return id;
    }
    try {
      final raw = await _apiOrThrow.get('/users/$id');
      _rememberUser(raw);
    } catch (_) {
      _users.putIfAbsent(id, () => {'id': id, 'handle': '', 'display_name': ''});
      _userIdByInt[qlUserInt(id)] = id;
    }
    return id;
  }

  // MARK: Chats

  String _chatTitle(_Conv c) {
    if (c.isGroup) return c.title.isEmpty ? '群聊' : c.title;
    final peer = c.peerId == null ? null : _users[c.peerId!];
    final name = _displayName(peer);
    if (name.isNotEmpty) return name;
    return c.title.isEmpty ? '轻聊用户' : c.title;
  }

  int _chatOrder(_Conv c) {
    final seconds = c.lastActivityMicros ~/ 1000000;
    var order = seconds <= 0 ? 1 : seconds * 100000 + (c.lastSeq % 100000);
    if (c.pinnedOrder > 0) {
      order = 9000000000000000 - c.pinnedOrder;
    }
    return order;
  }

  Map<String, dynamic> _position(_Conv c, {bool removed = false}) => {
    '@type': 'chatPosition',
    'list': c.archived
        ? {'@type': 'chatListArchive'}
        : {'@type': 'chatListMain'},
    'order': removed ? 0 : _chatOrder(c),
    'is_pinned': c.pinnedOrder > 0,
    'source': null,
  };

  int _lastReadInboxId(_Conv c) =>
      c.unread == 0 ? qlMessageId(math.max(c.readSeq, c.lastSeq)) : qlMessageId(c.readSeq);

  int _lastReadOutboxId(_Conv c) {
    if (!c.readReceiptsVisible) return 0;
    if (!c.isGroup) return qlMessageId(c.peerReadSeq);
    // Groups: the server exposes "read by N" for the latest message.
    if ((c.lastMessageReadCount ?? 0) > 0) return qlMessageId(c.lastSeq);
    return qlMessageId(c.peerReadSeq);
  }

  Map<String, dynamic> _notificationSettings(_Conv c) {
    final now = _nowSeconds();
    final muteFor = c.muteUntil > now ? math.min(c.muteUntil - now, 0x7FFFFFFF) : 0;
    return {
      '@type': 'chatNotificationSettings',
      'use_default_mute_for': c.muteUntil == 0,
      'mute_for': muteFor,
      'use_default_sound': true,
      'sound_id': -1,
      'use_default_show_preview': true,
      'show_preview': true,
      'use_default_mute_stories': true,
      'mute_stories': false,
      'use_default_story_sound': true,
      'story_sound_id': -1,
      'use_default_show_story_poster': true,
      'show_story_poster': true,
      'use_default_disable_pinned_message_notifications': true,
      'disable_pinned_message_notifications': false,
      'use_default_disable_mention_notifications': true,
      'disable_mention_notifications': false,
    };
  }

  Map<String, dynamic> _chatPermissions(_Conv c) {
    final admin = c.role == 'owner' || c.role == 'admin';
    return {
      '@type': 'chatPermissions',
      'can_send_basic_messages': !c.isChannel || admin,
      'can_send_audios': !c.isChannel || admin,
      'can_send_documents': !c.isChannel || admin,
      'can_send_photos': !c.isChannel || admin,
      'can_send_videos': !c.isChannel || admin,
      'can_send_video_notes': false,
      'can_send_voice_notes': !c.isChannel || admin,
      'can_send_polls': false,
      'can_send_other_messages': false,
      'can_add_link_previews': false,
      'can_change_info': c.isGroup && admin,
      'can_invite_users': c.isGroup && admin,
      'can_pin_messages': !c.isGroup || admin,
      'can_create_topics': false,
    };
  }

  Map<String, dynamic> _tdChat(_Conv c) {
    final avatar = c.isGroup
        ? c.avatarMediaId
        : (c.peerId == null ? '' : _users[c.peerId!]?['avatar_media_id']?.toString() ?? '');
    final blocked = !c.isGroup && c.peerId != null && _blockedUserIds.contains(c.peerId);
    final draft = c.draft['td'];
    Map<String, dynamic> type;
    if (c.isChannel) {
      type = {'@type': 'chatTypeSupergroup', 'supergroup_id': qlGroupInt(c.id), 'is_channel': true};
    } else if (c.isGroup) {
      type = {'@type': 'chatTypeBasicGroup', 'basic_group_id': qlGroupInt(c.id)};
    } else {
      type = {'@type': 'chatTypePrivate', 'user_id': qlUserInt(c.peerId ?? '')};
    }
    return {
      '@type': 'chat',
      'id': c.chatId,
      'type': type,
      'title': _chatTitle(c),
      'photo': _chatPhotoInfo(avatar),
      'accent_color_id': c.chatId.abs() % 7,
      'background_custom_emoji_id': 0,
      'upgraded_gift_colors': null,
      'profile_accent_color_id': -1,
      'profile_background_custom_emoji_id': 0,
      'permissions': _chatPermissions(c),
      'last_message': c.lastMessage,
      'positions': c.lastSeq == 0 && c.lastActivityMicros == 0 && c.pinnedOrder == 0
          ? [_position(c)]
          : [_position(c)],
      'chat_lists': [
        c.archived ? {'@type': 'chatListArchive'} : {'@type': 'chatListMain'},
      ],
      'message_sender_id': null,
      'block_list': blocked ? {'@type': 'blockListMain'} : null,
      'has_protected_content': false,
      'is_translatable': false,
      'is_marked_as_unread': c.manualUnread,
      'view_as_topics': false,
      'has_scheduled_messages': false,
      'can_be_deleted_only_for_self': false,
      'can_be_deleted_for_all_users': false,
      'can_be_reported': true,
      'default_disable_notification': false,
      'unread_count': c.unread,
      'last_read_inbox_message_id': _lastReadInboxId(c),
      'last_read_outbox_message_id': _lastReadOutboxId(c),
      'unread_mention_count': c.mentions,
      'unread_reaction_count': 0,
      'notification_settings': _notificationSettings(c),
      'available_reactions': {'@type': 'chatAvailableReactionsAll', 'max_reaction_count': 11},
      'message_auto_delete_time': 0,
      'emoji_status': null,
      'background': null,
      'theme': null,
      'action_bar': null,
      'business_bot_manage_bar': null,
      'video_chat': {
        '@type': 'videoChat',
        'group_call_id': 0,
        'has_participants': false,
        'default_participant_id': null,
      },
      'pending_join_requests': null,
      'reply_markup_message_id': 0,
      'draft_message': draft,
      'client_data': '',
    };
  }

  // MARK: Messages

  Map<String, dynamic> _sender(String userId) => {
    '@type': 'messageSenderUser',
    'user_id': qlUserInt(userId),
  };

  /// Converts a backend Message into a TDLib message (null for tombstones).
  Map<String, dynamic>? _tdMessage(_Conv c, Map<String, dynamic> m) {
    if (m['deleted'] == true) return null;
    final seq = QlTdEngine._int(m['conversation_seq']) ?? 0;
    final sender = m['sender_id']?.toString() ?? '';
    final outgoing = sender == _myId;
    final id = qlMessageId(seq);
    final date = _parseDate(m['created_at']);
    final edited = _parseDate(m['edited_at']);
    final replyTo = m['reply_to']?.toString() ?? '';
    Map<String, dynamic>? reply;
    if (replyTo.isNotEmpty) {
      final ref = _messageRef[replyTo];
      final replySeq = QlTdEngine._int(m['reply_to_seq']) ?? ref?.$2;
      reply = {
        '@type': 'messageReplyToMessage',
        'chat_id': c.chatId,
        'message_id': replySeq == null ? 0 : qlMessageId(replySeq),
        'quote': null,
        'checklist_task_id': 0,
        'origin': null,
        'origin_send_date': 0,
        'content': null,
      };
    }
    return {
      '@type': 'message',
      'id': id,
      'sender_id': _sender(sender),
      'chat_id': c.chatId,
      'sending_state': null,
      'scheduling_state': null,
      'is_outgoing': outgoing,
      'is_pinned': c.pinnedSeqs.contains(seq),
      'is_from_offline': false,
      'can_be_saved': true,
      'has_timestamped_media': false,
      'is_channel_post': c.isChannel && !outgoing,
      'is_paid_star_suggested_post': false,
      'is_paid_ton_suggested_post': false,
      'contains_unread_mention': false,
      'date': date,
      'edit_date': edited,
      'forward_info': _forwardInfo(m),
      'import_info': null,
      'interaction_info': _interactionInfo(c, seq),
      'unread_reactions': const <Object>[],
      'fact_check': null,
      'suggested_post_info': null,
      'reply_to': reply,
      'topic_id': null,
      'self_destruct_type': null,
      'self_destruct_in': 0.0,
      'auto_delete_in': 0.0,
      'via_bot_user_id': 0,
      'sender_business_bot_user_id': 0,
      'sender_boost_count': 0,
      'paid_message_star_count': 0,
      'author_signature': '',
      'media_album_id': _albumInt(m['album_id']?.toString() ?? ''),
      'effect_id': 0,
      'restriction_info': null,
      'summary_language_code': '',
      'content': _content(m),
      'reply_markup': null,
      // Not part of TDLib; kept for the engine's own bookkeeping.
      '@ql_id': m['id'],
      if (replyTo.isNotEmpty) '@ql_reply_to': replyTo,
    };
  }

  Map<String, dynamic> _content(Map<String, dynamic> m) {
    final kind = m['kind']?.toString() ?? 'text';
    final text = m['text']?.toString() ?? '';
    final caption = _formatted(text, _tdEntities(text, m['entities']));
    final mediaId = m['media_id']?.toString() ?? '';
    final meta = m['media'] is Map ? Map<String, dynamic>.from(m['media'] as Map) : const <String, dynamic>{};
    switch (kind) {
      case 'image':
        final dims = _mediaDims[mediaId];
        final w = QlTdEngine._int(meta['width']) ?? dims?[0] ?? 0;
        final h = QlTdEngine._int(meta['height']) ?? dims?[1] ?? 0;
        final file = _fileForMedia(mediaId, kind: 'image', size: QlTdEngine._int(meta['bytes']) ?? 0);
        return {
          '@type': 'messagePhoto',
          'photo': {
            '@type': 'photo',
            'has_stickers': false,
            'minithumbnail': null,
            'sizes': [
              {
                '@type': 'photoSize',
                'type': 'x',
                'photo': file,
                'width': w,
                'height': h,
                'progressive_sizes': const <int>[],
              },
            ],
          },
          'caption': caption,
          'show_caption_above_media': false,
          'has_spoiler': false,
          'is_secret': false,
        };
      case 'voice':
        return {
          '@type': 'messageVoiceNote',
          'voice_note': {
            '@type': 'voiceNote',
            'duration': _durationSec(meta),
            'waveform': meta['waveform']?.toString() ?? '',
            'mime_type': meta['mime']?.toString() ?? 'audio/ogg',
            'speech_recognition_result': null,
            'voice': _fileForMedia(mediaId, kind: 'voice', size: QlTdEngine._int(meta['bytes']) ?? 0),
          },
          'caption': caption,
          'is_listened': true,
        };
      case 'video':
        return _videoContent(m, meta, mediaId, caption);
      case 'file':
        final name = meta['file_name']?.toString() ?? '';
        return {
          '@type': 'messageDocument',
          'document': {
            '@type': 'document',
            'file_name': name.isEmpty ? '文件' : name,
            'mime_type': meta['mime']?.toString() ?? 'application/octet-stream',
            'minithumbnail': null,
            'thumbnail': null,
            'document': _fileForMedia(mediaId, kind: 'file', size: QlTdEngine._int(meta['bytes']) ?? 0, fileName: name),
          },
          'caption': caption,
        };
      case 'text':
        return {
          '@type': 'messageText',
          'text': caption,
          'link_preview': null,
          'link_preview_options': null,
        };
      default:
        // Unknown future kinds stay visible as their text instead of crashing.
        return {
          '@type': 'messageText',
          'text': _formatted(text.isEmpty ? '[暂不支持的消息]' : text),
          'link_preview': null,
          'link_preview_options': null,
        };
    }
  }

  /// Chat-list preview built from the conversation summary (which carries
  /// no timestamp of its own; last_activity stands in).
  Map<String, dynamic>? _lastMessageFromBrief(_Conv c, Map<String, dynamic>? brief) {
    if (brief == null) return null;
    final seq = QlTdEngine._int(brief['conversation_seq']) ?? 0;
    final cached = c.messages[seq];
    if (cached != null) return cached;
    if (brief['deleted'] == true) return null;
    final synthetic = <String, dynamic>{
      ...brief,
      'created_at': DateTime.fromMicrosecondsSinceEpoch(c.lastActivityMicros, isUtc: true).toIso8601String(),
    };
    return _tdMessage(c, synthetic);
  }

  void _cacheMessage(_Conv c, Map<String, dynamic> td, Map<String, dynamic> raw) {
    final seq = qlSeqOf(td['id'] as int);
    c.messages[seq] = td;
    final id = raw['id']?.toString() ?? '';
    if (id.isNotEmpty) _messageRef[id] = (c.id, seq);
    // Bound memory: keep the most recent 2000 per chat.
    while (c.messages.length > 2000) {
      c.messages.remove(c.messages.firstKey());
    }
  }

  Map<String, dynamic> _scopeNotificationSettings() => {
    '@type': 'scopeNotificationSettings',
    'mute_for': 0,
    'sound_id': -1,
    'show_preview': true,
    'use_default_mute_stories': true,
    'mute_stories': false,
    'story_sound_id': -1,
    'show_story_poster': true,
    'disable_pinned_message_notifications': false,
    'disable_mention_notifications': false,
  };
}
