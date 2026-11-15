part of 'ql_engine.dart';

int qlFolderInt(String id) {
  final v = _fnv1a64('fd:$id') & 0x7FFFFFFF;
  return v == 0 ? 1 : v;
}

int qlPackInt(String id) {
  final v = _fnv1a64('sp:$id') & 0x7FFFFFFFFFFFFFFF;
  return v == 0 ? 1 : v;
}

int qlStickerFileId(String id) =>
    (_fnv1a64('sf:$id') & 0x3FFFFFFF) | 0x40000000;

int qlPollInt(String id) {
  final v = _fnv1a64('po:$id') & 0x7FFFFFFFFFFFFFFF;
  return v == 0 ? 1 : v;
}

extension _QlP3 on QlTdEngine {
  Future<Map<String, dynamic>?> _dispatchP3(
    String type,
    Map<String, dynamic> r,
  ) async {
    switch (type) {
      case 'getInstalledStickerSets':
        return _installedStickerSets(r);
      case 'getStickerSet':
        return _getStickerSet(r);
      case 'getStickers':
      case 'searchStickers':
        return _searchStickersTd(r);
      case 'getRecentStickers':
      case 'getFavoriteStickers':
        return _favoriteStickers();
      case 'addFavoriteSticker':
        return _setFavoriteSticker(r, favorite: true);
      case 'removeFavoriteSticker':
        return _setFavoriteSticker(r, favorite: false);
      case 'setPollAnswer':
        return _setPollAnswer(r);
      case 'stopPoll':
        return _stopPoll(r);
      case 'markChecklistTasksAsDone':
        return _markChecklist(r);
      case 'editMessageChecklist':
        return _editChecklist(r);
      case 'addContact':
        return _addContact(r);
      case 'removeContacts':
        return _removeContacts(r);
      case 'getChatFolder':
        return _getChatFolder(r);
      case 'createChatFolder':
        return _upsertChatFolder(r, create: true);
      case 'editChatFolder':
        return _upsertChatFolder(r, create: false);
      case 'deleteChatFolder':
        return _deleteChatFolder(r);
      case 'reorderChatFolders':
        return _reorderChatFolders(r);
      case 'getRecommendedChatFolders':
        return {'@type': 'recommendedChatFolders', 'chat_folders': const <Object>[]};
      case 'getChatFolderChatsToLeave':
        return {'@type': 'chats', 'total_count': 0, 'chat_ids': const <int>[]};
      case 'setScopeNotificationSettings':
        return _setScopeNotifications(r);
      case 'getUserPrivacySettingRules':
        return _getPrivacyRules(r);
      case 'setUserPrivacySettingRules':
        return _setPrivacyRules(r);
      case 'getReadDatePrivacySettings':
        return _getReadDatePrivacy();
      case 'setReadDatePrivacySettings':
        return _setReadDatePrivacy(r);
      case 'getLinkPreview':
        return _getLinkPreview(r);
      case 'postStory':
        return _postStory(r);
      case 'editStory':
        return _editStoryTd(r);
      case 'deleteStory':
        return _deleteStoryTd(r);
      case 'getStory':
        return _getStoryTd(r);
      case 'openStory':
        return _openStoryTd(r);
      case 'closeStory':
        return _ok;
      case 'loadActiveStories':
        return _loadActiveStories(r);
      case 'getChatActiveStories':
        return _chatActiveStories(r);
      case 'getChatsToPostStories':
        return _chatsToPostStories();
      case 'canPostStory':
        return _canPostStory(r);
      case 'setStoryPrivacySettings':
        return _setStoryPrivacyTd(r);
      case 'setStoryReaction':
        return _setStoryReactionTd(r);
      case 'getStoryInteractions':
        return _storyInteractionsTd(r);
      case 'reportStory':
        return _reportStoryTd(r);
      case 'toggleStoryIsPostedToChatPage':
        return _toggleStoryPage(r);
      case 'getChatPostedToChatPageStories':
        return _listUserStoriesTd(r, archived: false);
      case 'getChatArchivedStories':
        return _listUserStoriesTd(r, archived: true);
      case 'getChatStoryAlbums':
        return _getChatStoryAlbums(r);
      case 'deleteChat':
        return _deleteChat(r);
      case 'setBio':
        return _setBio(r);
      case 'setUsername':
        return _setUsername(r);
      case 'setChatDescription':
        return _setChatDescription(r);
      case 'setChatSlowModeDelay':
        return _setChatSlowMode(r);
      case 'setChatPermissions':
        return _setChatPermissions(r);
      case 'setChatBackground':
        return _setChatBackground(r);
      case 'deleteChatBackground':
        return _deleteChatBackground(r);
      case 'setDefaultBackground':
        return _setDefaultBackground(r);
      case 'deleteDefaultBackground':
        return _deleteDefaultBackground(r);
      case 'createChatInviteLink':
        return _createChatInviteLink(r);
      case 'editChatInviteLink':
        return _editChatInviteLink(r);
      case 'revokeChatInviteLink':
        return _revokeChatInviteLink(r);
      case 'getChatInviteLinks':
        return _getChatInviteLinks(r);
      case 'getChatInviteLinkCounts':
        return _getChatInviteLinkCounts(r);
      case 'getChatInviteLinkMembers':
        return {'@type': 'chatInviteLinkMembers', 'total_count': 0, 'members': const <Object>[]};
      case 'checkChatInviteLink':
        return _checkChatInviteLink(r);
      case 'joinChatByInviteLink':
        return _joinChatByInviteLink(r);
      case 'getInternalLinkType':
        return _internalLinkType(r);
      case 'searchChatMembers':
        return _searchChatMembers(r);
      case 'deleteChatMessagesBySender':
        return _deleteChatMessagesBySender(r);
      case 'addPollOption':
        return _addPollOption(r);
      case 'canTransferOwnership':
        return {'@type': 'canTransferOwnershipResultOk'};
      case 'transferChatOwnership':
        return _transferChatOwnership(r);
      case 'upgradeBasicGroupChatToSupergroupChat':
        return _upgradeBasicGroup(r);
      case 'setChatMessageAutoDeleteTime':
        return _setAutoDelete(r);
      case 'toggleSupergroupIsAllHistoryAvailable':
        return _toggleHistory(r);
      case 'getMessageReadDate':
        return _messageReadDate(r);
      case 'getMessageViewers':
        return _messageViewers(r);
      case 'getCustomEmojiStickers':
        return _customEmojiStickers(r);
      case 'getChatScheduledMessages':
        return _scheduledMessages(r);
      case 'setSupergroupUsername':
        return _setSupergroupUsername(r);
      case 'toggleChatHasProtectedContent':
        return _setProtected(r);
      case 'toggleSupergroupJoinByRequest':
        return _setJoinByRequest(r);
      case 'getChatJoinRequests':
        return _joinRequests(r);
      case 'processChatJoinRequest':
        return _processJoinRequest(r);
      case 'processChatJoinRequests':
        return _processJoinRequests(r);
      default:
        return null;
    }
  }

  Future<void> _loadP3Extras() async {
    try {
      await _refreshContacts();
    } catch (_) {}
    try {
      await _refreshFolders();
    } catch (_) {}
    try {
      await _refreshScopeNotifications();
    } catch (_) {}
  }

  // MARK: Stickers

  Map<String, dynamic> _fileForSticker({
    required String stickerId,
    String mediaId = '',
    String fileId = '',
    int size = 0,
    String format = '',
  }) {
    final key = mediaId.isNotEmpty ? mediaId : 'sticker:$stickerId:${fileId.isEmpty ? stickerId : fileId}';
    final id = mediaId.isNotEmpty ? qlMediaFileId(mediaId) : qlStickerFileId(key);
    final f = _files.putIfAbsent(id, () => _QlFile(id));
    f.stickerId = stickerId;
    f.mediaId = mediaId;
    f.stickerFileId = fileId.isNotEmpty ? fileId : (mediaId.isEmpty ? stickerId : '');
    final ext = switch (format) {
      'webm' => '.webm',
      'tgs' => '.tgs',
      'png' => '.png',
      _ => '.webp',
    };
    f.kind = format == 'webm' ? 'video' : 'image';
    f.fileName = '$stickerId$ext';
    if (size > 0) f.size = size;
    if (f.localPath.isEmpty && _filesDir.isNotEmpty) {
      final path = f.mediaId.isNotEmpty
          ? _mediaPath(f.mediaId, f.kind, f.fileName)
          : '$_filesDir/qingliao/stickers/${f.stickerFileId}$ext';
      final file = File(path);
      if (file.existsSync()) {
        f.localPath = path;
        f.size = file.lengthSync();
        f.downloaded = f.size;
      }
    }
    return _tdFile(f);
  }

  Map<String, dynamic> _tdSticker(Map<String, dynamic> raw, {String packId = '', bool emoji = false}) {
    final sid = raw['id']?.toString() ?? '';
    final pack = raw['pack_id']?.toString() ?? packId;
    final emojiText = raw['emoji']?.toString() ?? '';
    final mediaId = raw['media_id']?.toString() ?? '';
    final fileId = raw['file_id']?.toString() ?? '';
    final format = raw['format']?.toString() ?? '';
    final isEmoji = emoji || raw['is_emoji'] == true;
    final file = _fileForSticker(stickerId: sid, mediaId: mediaId, fileId: fileId, format: format);
    final formatType = switch (format) {
      'webm' => 'stickerFormatWebm',
      'tgs' => 'stickerFormatTgs',
      'png' => 'stickerFormatPng',
      _ => 'stickerFormatWebp',
    };
    return {
      '@type': 'sticker',
      'id': qlPackInt('sticker:$sid'),
      'set_id': pack.isEmpty ? 0 : qlPackInt(pack),
      'width': 96,
      'height': 96,
      'emoji': emojiText,
      'format': {'@type': formatType},
      'full_type': isEmoji
          ? {'@type': 'stickerFullTypeCustomEmoji', 'custom_emoji_id': qlPackInt('emoji:$sid'), 'needs_repainting': false}
          : {'@type': 'stickerFullTypeRegular'},
      'thumbnail': {
        '@type': 'thumbnail',
        'format': {'@type': 'thumbnailFormatJpeg'},
        'width': 96,
        'height': 96,
        'file': file,
      },
      'sticker': file,
    };
  }

  Map<String, dynamic> _stickerSetInfo(Map<String, dynamic> pack, {List? covers}) {
    final id = pack['id']?.toString() ?? '';
    return {
      '@type': 'stickerSetInfo',
      'id': qlPackInt(id),
      'title': pack['title'] ?? '',
      'name': id,
      'thumbnail': null,
      'thumbnail_outline': const <Object>[],
      'is_owned': (pack['owner']?.toString() ?? '').isNotEmpty,
      'is_installed': true,
      'is_archived': false,
      'is_official': (pack['owner']?.toString() ?? '').isEmpty,
      'sticker_type': {'@type': pack['is_emoji'] == true ? 'stickerTypeCustomEmoji' : 'stickerTypeRegular'},
      'needs_repainting': false,
      'is_allowed_as_chat_emoji_status': false,
      'is_viewed': true,
      'size': covers?.length ?? 0,
      'covers': [for (final s in (covers ?? const []).take(1)) if (s is Map) _tdSticker(Map<String, dynamic>.from(s), packId: id, emoji: pack['is_emoji'] == true)],
    };
  }

  Future<Map<String, dynamic>> _installedStickerSets(Map<String, dynamic> r) async {
    final typ = r['sticker_type'];
    final wantEmoji = typ is Map && typ['@type'] == 'stickerTypeCustomEmoji';
    final raw = await _apiOrThrow.get('/sticker-packs');
    final packs = raw['packs'] is List ? raw['packs'] as List : const [];
    final sets = <Map<String, dynamic>>[];
    for (final p in packs) {
      if (p is! Map) continue;
      final pack = Map<String, dynamic>.from(p);
      if ((pack['is_emoji'] == true) != wantEmoji) continue;
      List? covers;
      try {
        final detail = await _apiOrThrow.get('/sticker-packs/${pack['id']}');
        covers = detail['stickers'] is List ? detail['stickers'] as List : null;
      } catch (_) {}
      sets.add(_stickerSetInfo(pack, covers: covers));
    }
    return {'@type': 'stickerSets', 'total_count': sets.length, 'sets': sets};
  }

  Future<Map<String, dynamic>> _getStickerSet(Map<String, dynamic> r) async {
    final setId = QlTdEngine._int(r['set_id']) ?? 0;
    final raw = await _apiOrThrow.get('/sticker-packs');
    final packs = raw['packs'] is List ? raw['packs'] as List : const [];
    String? packId;
    Map<String, dynamic>? pack;
    for (final p in packs) {
      if (p is! Map) continue;
      final m = Map<String, dynamic>.from(p);
      if (qlPackInt(m['id']?.toString() ?? '') == setId) {
        packId = m['id']?.toString();
        pack = m;
        break;
      }
    }
    if (packId == null || pack == null) return _error(404, 'Sticker set not found');
    final detail = await _apiOrThrow.get('/sticker-packs/$packId');
    final stickers = [
      for (final s in (detail['stickers'] as List? ?? const []))
        if (s is Map) _tdSticker(Map<String, dynamic>.from(s), packId: packId, emoji: pack['is_emoji'] == true),
    ];
    return {
      '@type': 'stickerSet',
      'id': setId,
      'title': pack['title'] ?? detail['title'] ?? '',
      'name': packId,
      'thumbnail': null,
      'thumbnail_outline': const <Object>[],
      'is_owned': (pack['owner']?.toString() ?? '').isNotEmpty,
      'is_installed': true,
      'is_archived': false,
      'is_official': (pack['owner']?.toString() ?? '').isEmpty,
      'sticker_type': {'@type': pack['is_emoji'] == true ? 'stickerTypeCustomEmoji' : 'stickerTypeRegular'},
      'needs_repainting': false,
      'is_allowed_as_chat_emoji_status': false,
      'is_viewed': true,
      'stickers': stickers,
      'emojis': [
        for (final s in stickers)
          {
            '@type': 'stickerEmojis',
            'emojis': [s['emoji'] ?? ''],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _searchStickersTd(Map<String, dynamic> r) async {
    final q = r['emojis']?.toString() ?? r['query']?.toString() ?? r['emoji']?.toString() ?? '';
    final raw = await _apiOrThrow.get('/stickers', {'q': q});
    final stickers = [
      for (final s in (raw['stickers'] as List? ?? const []))
        if (s is Map) _tdSticker(Map<String, dynamic>.from(s)),
    ];
    return {'@type': 'stickers', 'stickers': stickers};
  }

  Future<Map<String, dynamic>> _favoriteStickers() async {
    final raw = await _apiOrThrow.get('/me/sticker-favorites');
    final stickers = [
      for (final s in (raw['stickers'] as List? ?? const []))
        if (s is Map) _tdSticker(Map<String, dynamic>.from(s)),
    ];
    return {'@type': 'stickers', 'stickers': stickers};
  }

  Future<Map<String, dynamic>> _setFavoriteSticker(
    Map<String, dynamic> r, {
    required bool favorite,
  }) async {
    final sticker = r['sticker'];
    String sid = '';
    if (sticker is Map) {
      if (sticker['@type'] == 'inputFileRemote') {
        sid = sticker['id']?.toString() ?? '';
      } else if (sticker['@type'] == 'inputFileId') {
        final f = _files[QlTdEngine._int(sticker['id']) ?? 0];
        sid = f?.stickerId ?? '';
      }
    }
    if (sid.isEmpty) return _error(400, 'sticker required');
    await _apiOrThrow.put('/me/sticker-favorites/$sid', {'favorite': favorite});
    return _ok;
  }

  String? _stickerIdFromInput(Map input) {
    var sticker = input['sticker'];
    if (sticker is Map && sticker['@type'] == 'inputSticker') {
      sticker = sticker['sticker'];
    }
    if (sticker is! Map) return null;
    switch (sticker['@type']) {
      case 'inputFileRemote':
        return sticker['id']?.toString();
      case 'inputFileId':
        return _files[QlTdEngine._int(sticker['id']) ?? 0]?.stickerId;
      default:
        return sticker['id']?.toString();
    }
  }

  Future<Map<String, dynamic>> _sendSpecial(
    Map<String, dynamic> r, {
    required String kind,
    required Map<String, dynamic> content,
    required Future<Map<String, dynamic>> Function(_Conv c, String clientId, String replyTo) deliver,
  }) async {
    final c0 = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c0 == null) return _error(400, 'Chat not found');
    String replyTo = '';
    final reply = r['reply_to'];
    if (reply is Map && reply['@type'] == 'inputMessageReplyToMessage') {
      final target = QlTdEngine._int(reply['message_id']) ?? 0;
      replyTo = c0.messages[qlSeqOf(target)]?['@ql_id']?.toString() ?? '';
    }
    final tempId = qlMessageId(c0.lastSeq) + (++_pendingCounter % 0xFFFFE) + 1;
    final clientMsgId = _newClientMsgId();
    final message = <String, dynamic>{
      '@type': 'message',
      'id': tempId,
      'sender_id': _sender(_myId),
      'chat_id': c0.chatId,
      'sending_state': {'@type': 'messageSendingStatePending', 'sending_id': _pendingCounter},
      'is_outgoing': true,
      'is_pinned': false,
      'date': _nowSeconds(),
      'edit_date': 0,
      'content': content,
      'reply_markup': null,
    };
    final pending = _Pending(conv: c0, tempId: tempId, clientMsgId: clientMsgId, message: message);
    _pendingByClientId[clientMsgId] = pending;
    _pendingByTempId[tempId] = pending;
    _emit({'@type': 'updateNewMessage', 'message': message});
    unawaited(() async {
      try {
        var c = pending.conv;
        if (c.id.startsWith('virtual:')) {
          c = await _materialize(c);
          pending.conv = c;
        }
        final sent = await deliver(c, clientMsgId, replyTo);
        _completePending(pending, sent);
      } catch (e) {
        final code = e is QlApiException ? _tdCode(e.statusCode) : 500;
        final error = {'@type': 'error', 'code': code, 'message': e is QlApiException ? _humanError(e) : '发送失败，请检查网络'};
        pending.message = {
          ...pending.message,
          'sending_state': {
            '@type': 'messageSendingStateFailed',
            'error': error,
            'can_retry': false,
            'need_another_sender': false,
            'need_another_reply_quote': false,
            'need_drop_reply': false,
            'required_paid_message_star_count': 0,
            'retry_after': 0.0,
          },
        };
        _emit({'@type': 'updateMessageSendFailed', 'message': pending.message, 'old_message_id': tempId, 'error': error});
      }
    }());
    return message;
  }

  Future<Map<String, dynamic>> _sendStickerMessage(Map<String, dynamic> r, Map input) async {
    final sid = _stickerIdFromInput(input);
    if (sid == null || sid.isEmpty) return _error(400, 'sticker required');
    final emoji = input['emoji']?.toString() ?? '';
    return _sendSpecial(
      r,
      kind: 'sticker',
      content: {
        '@type': 'messageSticker',
        'sticker': _tdSticker({'id': sid, 'emoji': emoji, 'media_id': '', 'file_id': sid}),
        'is_premium': false,
      },
      deliver: (c, clientId, replyTo) => _apiOrThrow.post('/conversations/${c.id}/messages', {
        'client_msg_id': clientId,
        'kind': 'sticker',
        'sticker_id': sid,
        'text': emoji,
        'reply_to': replyTo,
      }),
    );
  }

  Future<Map<String, dynamic>> _sendPollMessage(Map<String, dynamic> r, Map input) async {
    final question = (input['question'] is Map ? input['question']['text'] : input['question'])?.toString() ?? '';
    final options = <String>[];
    for (final o in (input['options'] as List? ?? const [])) {
      if (o is Map) {
        final text = o['text'] is Map ? o['text']['text'] : o['text'];
        if (text != null && text.toString().trim().isNotEmpty) options.add(text.toString().trim());
      } else if (o != null && o.toString().trim().isNotEmpty) {
        options.add(o.toString().trim());
      }
    }
    final typ = input['type'] is Map ? Map<String, dynamic>.from(input['type'] as Map) : const <String, dynamic>{};
    final quiz = typ['@type'] == 'inputPollTypeQuiz';
    int? correct;
    if (quiz) {
      final ids = typ['correct_option_ids'];
      if (ids is List && ids.isNotEmpty) correct = QlTdEngine._int(ids.first);
    }
    final period = QlTdEngine._int(input['open_period']) ?? 0;
    return _sendSpecial(
      r,
      kind: 'poll',
      content: _pollContent({
        'question': question,
        'options': [for (var i = 0; i < options.length; i++) {'id': i, 'text': options[i], 'voter_count': 0, 'chosen': false}],
        'total_voter_count': 0,
        'anonymous': input['is_anonymous'] != false,
        'multiple_choice': input['allows_multiple_answers'] == true,
        'quiz': quiz,
        'closed': false,
        if (correct != null) 'correct_option': correct,
      }),
      deliver: (c, clientId, replyTo) => _apiOrThrow.post('/conversations/${c.id}/polls', {
        'question': question,
        'options': options,
        'multiple_choice': input['allows_multiple_answers'] == true,
        'anonymous': input['is_anonymous'] != false,
        'quiz': quiz,
        if (correct != null) 'correct_option': correct,
        if (period > 0) 'closes_at': DateTime.now().toUtc().add(Duration(seconds: period)).toIso8601String(),
        'client_msg_id': clientId,
      }),
    );
  }

  Future<Map<String, dynamic>> _sendChecklistMessage(Map<String, dynamic> r, Map input) async {
    final list = input['checklist'] is Map ? Map<String, dynamic>.from(input['checklist'] as Map) : input;
    final title = (list['title'] is Map ? list['title']['text'] : list['title'])?.toString() ?? '';
    final tasks = <String>[];
    for (final t in (list['tasks'] as List? ?? const [])) {
      if (t is Map) {
        final text = t['text'] is Map ? t['text']['text'] : t['text'];
        if (text != null && text.toString().trim().isNotEmpty) tasks.add(text.toString().trim());
      }
    }
    return _sendSpecial(
      r,
      kind: 'checklist',
      content: _checklistContent({
        'title': title,
        'tasks': [for (var i = 0; i < tasks.length; i++) {'id': i + 1, 'text': tasks[i], 'completed_by': '', 'completed_at': ''}],
        'others_can_add': list['others_can_add_tasks'] == true,
        'others_can_mark': list['others_can_mark_tasks_as_done'] != false,
        'creator_id': _myId,
      }),
      deliver: (c, clientId, replyTo) => _apiOrThrow.post('/conversations/${c.id}/checklists', {
        'title': title,
        'tasks': tasks,
        'others_can_add': list['others_can_add_tasks'] == true,
        'others_can_mark': list['others_can_mark_tasks_as_done'] != false,
        'client_msg_id': clientId,
      }),
    );
  }

  Map<String, dynamic> _pollContent(Map poll) {
    final options = poll['options'] is List ? poll['options'] as List : const [];
    final total = QlTdEngine._int(poll['total_voter_count']) ?? 0;
    final closed = poll['closed'] == true;
    final quiz = poll['quiz'] == true;
    return {
      '@type': 'messagePoll',
      'poll': {
        '@type': 'poll',
        'id': qlPollInt(poll['id']?.toString() ?? poll['question']?.toString() ?? ''),
        'question': _formatted(poll['question']?.toString() ?? ''),
        'options': [
          for (final o in options)
            if (o is Map)
              {
                '@type': 'pollOption',
                'id': '${o['id'] ?? ''}',
                'text': _formatted(o['text']?.toString() ?? ''),
                'voter_count': QlTdEngine._int(o['voter_count']) ?? 0,
                'vote_percentage': total <= 0
                    ? 0
                    : (((QlTdEngine._int(o['voter_count']) ?? 0) * 100) / total).round(),
                'is_chosen': o['chosen'] == true,
                'is_being_chosen': false,
              },
        ],
        'total_voter_count': total,
        'recent_voter_ids': const <Object>[],
        'is_anonymous': poll['anonymous'] != false,
        'type': quiz
            ? {
                '@type': 'pollTypeQuiz',
                'correct_option_ids': [
                  if (poll['correct_option'] != null) QlTdEngine._int(poll['correct_option']) ?? 0,
                ],
                'explanation': _formatted(''),
              }
            : {'@type': 'pollTypeRegular', 'allow_adding_options': false},
        'open_period': 0,
        'close_date': QlTdEngine._int(poll['closes_at']) ?? 0,
        'is_closed': closed,
        'can_get_voters': poll['anonymous'] == false && !closed,
        'can_see_results': true,
        'allows_multiple_answers': poll['multiple_choice'] == true,
        'allows_revoting': !quiz,
      },
    };
  }

  Map<String, dynamic> _checklistContent(Map list) {
    final tasks = list['tasks'] is List ? list['tasks'] as List : const [];
    final othersAdd = list['others_can_add'] == true;
    final othersMark = list['others_can_mark'] != false;
    final creator = list['creator_id']?.toString() ?? '';
    final mine = creator == _myId || creator.isEmpty;
    return {
      '@type': 'messageChecklist',
      'list': {
        '@type': 'checklist',
        'title': _formatted(list['title']?.toString() ?? ''),
        'tasks': [
          for (final t in tasks)
            if (t is Map)
              {
                '@type': 'checklistTask',
                'id': QlTdEngine._int(t['id']) ?? 0,
                'text': _formatted(t['text']?.toString() ?? ''),
                'completed_by': (t['completed_by']?.toString() ?? '').isEmpty
                    ? null
                    : _sender(t['completed_by'].toString()),
                'completion_date': _parseDate(t['completed_at']),
              },
        ],
        'others_can_add_tasks': othersAdd,
        'can_add_tasks': mine || othersAdd,
        'others_can_mark_tasks_as_done': othersMark,
        'can_mark_tasks_as_done': mine || othersMark,
      },
    };
  }

  Future<Map<String, dynamic>> _setPollAnswer(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final mid = QlTdEngine._int(r['message_id']) ?? 0;
    if (c == null) return _error(400, 'Chat not found');
    final td = c.messages[qlSeqOf(mid)];
    final qlId = td?['@ql_id']?.toString() ?? '';
    final pollId = (td?['content'] is Map ? (td!['content'] as Map)['@ql_poll_id'] : null)?.toString() ?? '';
    if (qlId.isEmpty || pollId.isEmpty) return _error(400, 'Poll not found');
    final options = [
      for (final v in (r['option_ids'] as List? ?? const []))
        if (QlTdEngine._int(v) != null) QlTdEngine._int(v)!,
    ];
    final raw = await _apiOrThrow.post('/conversations/${c.id}/polls/$pollId/vote', {'option_ids': options});
    final updated = _tdMessage(c, raw);
    if (updated != null) {
      _cacheMessage(c, updated, raw);
      _emit({'@type': 'updateMessageContent', 'chat_id': c.chatId, 'message_id': updated['id'], 'new_content': updated['content']});
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _stopPoll(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final mid = QlTdEngine._int(r['message_id']) ?? 0;
    if (c == null) return _error(400, 'Chat not found');
    final td = c.messages[qlSeqOf(mid)];
    final pollId = (td?['content'] is Map ? (td!['content'] as Map)['@ql_poll_id'] : null)?.toString() ?? '';
    if (pollId.isEmpty) return _error(400, 'Poll not found');
    final raw = await _apiOrThrow.post('/conversations/${c.id}/polls/$pollId/close');
    final updated = _tdMessage(c, raw);
    if (updated != null) {
      _cacheMessage(c, updated, raw);
      _emit({'@type': 'updateMessageContent', 'chat_id': c.chatId, 'message_id': updated['id'], 'new_content': updated['content']});
    }
    return _ok;
  }

  String _qlIdOf(int chatId, int messageId) {
    final c = _conv(chatId);
    return c?.messages[qlSeqOf(messageId)]?['@ql_id']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _markChecklist(Map<String, dynamic> r) async {
    final id = _qlIdOf(QlTdEngine._int(r['chat_id']) ?? 0, QlTdEngine._int(r['message_id']) ?? 0);
    if (id.isEmpty) return _error(400, 'Message not found');
    await _apiOrThrow.post('/messages/$id/checklist/done', {
      'done_task_ids': r['marked_as_done_task_ids'] ?? const <int>[],
      'undone_task_ids': r['marked_as_not_done_task_ids'] ?? const <int>[],
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _editChecklist(Map<String, dynamic> r) async {
    final id = _qlIdOf(QlTdEngine._int(r['chat_id']) ?? 0, QlTdEngine._int(r['message_id']) ?? 0);
    if (id.isEmpty) return _error(400, 'Message not found');
    final list = r['checklist'] is Map ? Map<String, dynamic>.from(r['checklist'] as Map) : <String, dynamic>{};
    final title = (list['title'] is Map ? list['title']['text'] : list['title'])?.toString() ?? '';
    final tasks = <Map<String, dynamic>>[];
    for (final t in (list['tasks'] as List? ?? const [])) {
      if (t is! Map) continue;
      final text = t['text'] is Map ? t['text']['text'] : t['text'];
      tasks.add({'id': t['id'], 'text': text?.toString() ?? ''});
    }
    await _apiOrThrow.patch('/messages/$id/checklist', {
      'title': title,
      'tasks': tasks,
      if (list.containsKey('others_can_add_tasks')) 'others_can_add': list['others_can_add_tasks'] == true,
      if (list.containsKey('others_can_mark_tasks_as_done')) 'others_can_mark': list['others_can_mark_tasks_as_done'] == true,
    });
    return _ok;
  }

  // MARK: Contacts

  Future<void> _refreshContacts() async {
    final raw = await _apiOrThrow.get('/me/contacts');
    _contactIds
      ..clear()
      ..addAll([
        for (final c in (raw['contacts'] as List? ?? const []))
          if (c is Map && (c['user_id']?.toString() ?? '').isNotEmpty && c['user_id'].toString() != _myId)
            c['user_id'].toString(),
      ]);
    for (final id in _contactIds) {
      try {
        await _ensureUser(id);
      } catch (_) {}
    }
    _emit({
      '@type': 'updateContacts',
      'user_ids': [for (final id in _contactIds) qlUserInt(id)],
    });
  }

  Future<Map<String, dynamic>> _getContactsTd() async {
    await _waitInitialLoad();
    try {
      await _refreshContacts();
    } catch (_) {}
    final ids = [for (final id in _contactIds) qlUserInt(id)];
    return {'@type': 'users', 'total_count': ids.length, 'user_ids': ids};
  }

  Future<Map<String, dynamic>> _addContact(Map<String, dynamic> r) async {
    final uid = _userIdByInt[QlTdEngine._int(r['user_id']) ?? 0];
    if (uid == null) return _error(400, 'User not found');
    final contact = r['contact'] is Map ? Map<String, dynamic>.from(r['contact'] as Map) : <String, dynamic>{};
    await _apiOrThrow.put('/me/contacts/$uid', {
      'first_name': contact['first_name'] ?? '',
      'last_name': contact['last_name'] ?? '',
    });
    _contactIds.add(uid);
    try {
      await _ensureUser(uid);
    } catch (_) {}
    _emit({'@type': 'updateUser', 'user': _tdUser(uid)});
    return _ok;
  }

  Future<Map<String, dynamic>> _removeContacts(Map<String, dynamic> r) async {
    for (final v in (r['user_ids'] as List? ?? const [])) {
      final uid = _userIdByInt[QlTdEngine._int(v) ?? 0];
      if (uid == null) continue;
      try {
        await _apiOrThrow.delete('/me/contacts/$uid');
        _contactIds.remove(uid);
      } catch (_) {}
    }
    return _ok;
  }

  // MARK: Folders

  Future<void> _refreshFolders() async {
    final raw = await _apiOrThrow.get('/folders');
    _folders.clear();
    _folderIdByInt.clear();
    for (final f in (raw['folders'] as List? ?? const [])) {
      if (f is! Map) continue;
      final m = Map<String, dynamic>.from(f);
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _folders[id] = m;
      _folderIdByInt[qlFolderInt(id)] = id;
    }
    _emit(_chatFoldersUpdate());
  }

  Map<String, dynamic> _chatFoldersUpdate() {
    final ordered = _folders.values.toList()
      ..sort((a, b) => (QlTdEngine._int(a['sort_order']) ?? 0).compareTo(QlTdEngine._int(b['sort_order']) ?? 0));
    return {
      '@type': 'updateChatFolders',
      'chat_folders': [for (final f in ordered) _chatFolderInfo(f)],
      'main_chat_list_position': _mainChatListPosition,
      'are_tags_enabled': false,
    };
  }

  Map<String, dynamic> _chatFolderInfo(Map<String, dynamic> f) {
    final name = f['name']?.toString() ?? '';
    return {
      '@type': 'chatFolderInfo',
      'id': qlFolderInt(f['id']?.toString() ?? ''),
      'name': {
        '@type': 'chatFolderName',
        'text': _formatted(name),
        'animate_custom_emoji': false,
      },
      'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
      'color_id': -1,
      'is_shareable': false,
      'has_my_invite_links': false,
    };
  }

  Map<String, dynamic> _tdChatFolder(Map<String, dynamic> f) {
    final filter = f['filter'] is Map ? Map<String, dynamic>.from(f['filter'] as Map) : <String, dynamic>{};
    final include = [
      for (final id in (filter['include_chat_ids'] as List? ?? const []))
        if (_convs[id.toString()]?.chatId != null) _convs[id.toString()]!.chatId,
    ];
    final exclude = [
      for (final id in (filter['exclude_chat_ids'] as List? ?? const []))
        if (_convs[id.toString()]?.chatId != null) _convs[id.toString()]!.chatId,
    ];
    final types = [for (final t in (filter['types'] as List? ?? const [])) t.toString()];
    return {
      '@type': 'chatFolder',
      'name': {
        '@type': 'chatFolderName',
        'text': _formatted(f['name']?.toString() ?? ''),
        'animate_custom_emoji': false,
      },
      'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
      'color_id': -1,
      'is_shareable': false,
      'pinned_chat_ids': const <int>[],
      'included_chat_ids': include,
      'excluded_chat_ids': exclude,
      'exclude_muted': false,
      'exclude_read': filter['unread_only'] == true,
      'exclude_archived': true,
      'include_contacts': types.isEmpty || types.contains('direct'),
      'include_non_contacts': types.isEmpty || types.contains('direct'),
      'include_bots': false,
      'include_groups': types.isEmpty || types.contains('group'),
      'include_channels': types.isEmpty || types.contains('channel'),
    };
  }

  Future<Map<String, dynamic>> _getChatFolder(Map<String, dynamic> r) async {
    if (_folders.isEmpty) {
      try {
        await _refreshFolders();
      } catch (_) {}
    }
    final id = _folderIdByInt[QlTdEngine._int(r['chat_folder_id']) ?? 0];
    final f = id == null ? null : _folders[id];
    if (f == null) return _error(404, 'Folder not found');
    return _tdChatFolder(f);
  }

  Map<String, dynamic> _folderFilterFromTd(Map folder) {
    final includeIds = <String>[];
    for (final v in (folder['included_chat_ids'] as List? ?? const [])) {
      final c = _conv(QlTdEngine._int(v) ?? 0);
      if (c != null && !c.id.startsWith('virtual:')) includeIds.add(c.id);
    }
    final excludeIds = <String>[];
    for (final v in (folder['excluded_chat_ids'] as List? ?? const [])) {
      final c = _conv(QlTdEngine._int(v) ?? 0);
      if (c != null) excludeIds.add(c.id);
    }
    final types = <String>[];
    if (folder['include_groups'] == true) types.add('group');
    if (folder['include_channels'] == true) types.add('channel');
    if (folder['include_contacts'] == true || folder['include_non_contacts'] == true) types.add('direct');
    return {
      'include_chat_ids': includeIds,
      'exclude_chat_ids': excludeIds,
      'types': types,
      'unread_only': folder['exclude_read'] == true,
    };
  }

  Future<Map<String, dynamic>> _upsertChatFolder(Map<String, dynamic> r, {required bool create}) async {
    final folder = r['folder'] is Map ? Map<String, dynamic>.from(r['folder'] as Map) : <String, dynamic>{};
    final title = folder['name'] is Map
        ? ((folder['name']['text'] is Map ? folder['name']['text']['text'] : folder['name']['text'])?.toString() ?? '')
        : folder['title']?.toString() ?? '';
    if (title.trim().isEmpty) return _error(400, 'Folder name required');
    final body = {'name': title.trim(), 'filter': _folderFilterFromTd(folder), 'sort_order': _folders.length};
    if (create) {
      final res = await _apiOrThrow.post('/folders', body);
      await _refreshFolders();
      final id = res['id']?.toString() ?? '';
      return {'@type': 'chatFolderInfo', 'id': qlFolderInt(id), ..._chatFolderInfo(_folders[id] ?? {'id': id, 'name': title})};
    }
    final id = _folderIdByInt[QlTdEngine._int(r['chat_folder_id']) ?? 0];
    if (id == null) return _error(404, 'Folder not found');
    await _apiOrThrow.patch('/folders/$id', body);
    await _refreshFolders();
    return _ok;
  }

  Future<Map<String, dynamic>> _deleteChatFolder(Map<String, dynamic> r) async {
    final id = _folderIdByInt[QlTdEngine._int(r['chat_folder_id']) ?? 0];
    if (id == null) return _error(404, 'Folder not found');
    await _apiOrThrow.delete('/folders/$id');
    await _refreshFolders();
    return _ok;
  }

  Future<Map<String, dynamic>> _reorderChatFolders(Map<String, dynamic> r) async {
    final ids = [for (final v in (r['chat_folder_ids'] as List? ?? const [])) QlTdEngine._int(v) ?? 0];
    _mainChatListPosition = QlTdEngine._int(r['main_chat_list_position']) ?? 0;
    var order = 0;
    for (final n in ids) {
      final id = _folderIdByInt[n];
      if (id == null) continue;
      final f = _folders[id];
      if (f == null) continue;
      await _apiOrThrow.patch('/folders/$id', {
        'name': f['name'],
        'filter': f['filter'] ?? {'include_chat_ids': [], 'exclude_chat_ids': [], 'types': [], 'unread_only': false},
        'sort_order': order++,
      });
    }
    await _refreshFolders();
    return _ok;
  }

  bool _convMatchesFolder(_Conv c, Map<String, dynamic> folder) {
    final filter = folder['filter'] is Map ? Map<String, dynamic>.from(folder['filter'] as Map) : <String, dynamic>{};
    final exclude = [for (final id in (filter['exclude_chat_ids'] as List? ?? const [])) id.toString()];
    if (exclude.contains(c.id)) return false;
    if (c.archived) return false;
    final include = [for (final id in (filter['include_chat_ids'] as List? ?? const [])) id.toString()];
    final types = [for (final t in (filter['types'] as List? ?? const [])) t.toString()];
    final unreadOnly = filter['unread_only'] == true;
    if (unreadOnly && c.unread <= 0 && !c.manualUnread) return false;
    if (include.isEmpty && types.isEmpty) return true;
    if (include.contains(c.id)) return true;
    final kind = c.isChannel ? 'channel' : (c.isGroup ? 'group' : 'direct');
    return types.contains(kind);
  }

  // MARK: Notifications & privacy

  Future<void> _refreshScopeNotifications() async {
    final raw = await _apiOrThrow.get('/me/notification-scopes');
    _scopeNotifs.clear();
    for (final s in (raw['scopes'] as List? ?? const [])) {
      if (s is Map && s['scope'] != null) {
        _scopeNotifs[s['scope'].toString()] = Map<String, dynamic>.from(s);
      }
    }
  }

  String _scopeName(Object? scope) {
    final t = scope is Map ? scope['@type']?.toString() : scope?.toString();
    return switch (t) {
      'notificationSettingsScopeGroupChats' => 'group',
      'notificationSettingsScopeChannelChats' => 'channel',
      _ => 'private',
    };
  }

  Map<String, dynamic> _scopeSettingsTd(String scope) {
    final raw = _scopeNotifs[scope];
    final until = QlTdEngine._int(raw?['mute_until']) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final muteFor = until <= now ? 0 : until - now;
    return {
      '@type': 'scopeNotificationSettings',
      'mute_for': muteFor,
      'sound_id': -1,
      'show_preview': raw == null ? true : raw['show_preview'] != false,
      'use_default_mute_stories': true,
      'mute_stories': false,
      'story_sound_id': -1,
      'show_story_poster': true,
      'disable_pinned_message_notifications': false,
      'disable_mention_notifications': false,
    };
  }

  Future<Map<String, dynamic>> _getScopeNotifications(Map<String, dynamic> r) async {
    final scope = _scopeName(r['scope']);
    if (_scopeNotifs.isEmpty) {
      try {
        await _refreshScopeNotifications();
      } catch (_) {}
    }
    return _scopeSettingsTd(scope);
  }

  Future<Map<String, dynamic>> _setScopeNotifications(Map<String, dynamic> r) async {
    final scope = _scopeName(r['scope']);
    final s = r['notification_settings'] is Map ? Map<String, dynamic>.from(r['notification_settings'] as Map) : <String, dynamic>{};
    final muteFor = QlTdEngine._int(s['mute_for']) ?? 0;
    var muteUntil = 0;
    if (muteFor >= 366 * 86400) {
      muteUntil = 4102444800;
    } else if (muteFor > 0) {
      muteUntil = DateTime.now().millisecondsSinceEpoch ~/ 1000 + muteFor;
    }
    await _apiOrThrow.put('/me/notification-scopes/$scope', {
      'mute_until': muteUntil,
      'show_preview': s['show_preview'] != false,
    });
    _scopeNotifs[scope] = {'scope': scope, 'mute_until': muteUntil, 'show_preview': s['show_preview'] != false};
    _emit({
      '@type': 'updateScopeNotificationSettings',
      'scope': r['scope'] ?? {'@type': 'notificationSettingsScopePrivateChats'},
      'notification_settings': _scopeSettingsTd(scope),
    });
    return _ok;
  }

  String _privacySettingName(Object? setting) {
    if (setting is Map) return setting['@type']?.toString() ?? '';
    return setting?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _getPrivacyRules(Map<String, dynamic> r) async {
    final setting = _privacySettingName(r['setting']);
    if (setting.isEmpty) return _error(400, 'setting required');
    final raw = await _apiOrThrow.get('/me/privacy/rules', {'setting': setting});
    final rulesMap = raw['rules'];
    Object? stored;
    if (rulesMap is Map) stored = rulesMap[setting];
    List rules;
    if (stored is List) {
      rules = stored;
    } else if (stored is Map && stored['rules'] is List) {
      rules = stored['rules'] as List;
    } else {
      rules = [
        {'@type': 'userPrivacySettingRuleAllowAll'},
      ];
    }
    return {
      '@type': 'userPrivacySettingRules',
      'rules': [for (final e in rules) if (e is Map) Map<String, dynamic>.from(e)],
    };
  }

  Future<Map<String, dynamic>> _setPrivacyRules(Map<String, dynamic> r) async {
    final setting = _privacySettingName(r['setting']);
    final rules = r['rules'];
    final payload = rules is Map ? rules['rules'] ?? rules : rules;
    await _apiOrThrow.put('/me/privacy/rules', {'setting': setting, 'rules': payload});
    _emit({
      '@type': 'updateUserPrivacySettingRules',
      'setting': {'@type': setting},
      'rules': {'@type': 'userPrivacySettingRules', 'rules': payload is List ? payload : const <Object>[]},
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _getReadDatePrivacy() async {
    final raw = await _apiOrThrow.get('/me/privacy');
    return {
      '@type': 'readDatePrivacySettings',
      'show_read_date': raw['read_receipts_enabled'] != false,
    };
  }

  Future<Map<String, dynamic>> _setReadDatePrivacy(Map<String, dynamic> r) async {
    final settings = r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : <String, dynamic>{};
    final on = settings['show_read_date'] != false;
    await _apiOrThrow.put('/me/privacy', {'read_receipts_enabled': on});
    return {'@type': 'readDatePrivacySettings', 'show_read_date': on};
  }

  Future<Map<String, dynamic>> _getLinkPreview(Map<String, dynamic> r) async {
    var url = r['url']?.toString() ?? '';
    if (url.isEmpty && r['text'] is Map) {
      url = (r['text']['text']?.toString() ?? '');
      final match = _urlPattern.firstMatch(url);
      url = match == null ? '' : url.substring(match.start, match.end);
    }
    if (url.isEmpty) return _error(400, 'url required');
    try {
      final raw = await _apiOrThrow.post('/link-previews', {'url': url});
      return _tdLinkPreview(raw);
    } on QlApiException catch (e) {
      return _error(_tdCode(e.statusCode), '预览不可用');
    }
  }

  Map<String, dynamic> _tdLinkPreview(Map raw) {
    final url = raw['url']?.toString() ?? '';
    final image = raw['image']?.toString() ?? '';
    final previewId = raw['id']?.toString() ?? '';
    Map<String, dynamic>? photo;
    if (image.isNotEmpty && previewId.isNotEmpty) {
      final id = qlMediaFileId('preview:$previewId');
      final f = _files.putIfAbsent(id, () => _QlFile(id));
      f.previewId = previewId;
      f.kind = 'image';
      f.fileName = '$previewId.jpg';
      photo = {
        '@type': 'photo',
        'has_stickers': false,
        'minithumbnail': null,
        'sizes': [
          {
            '@type': 'photoSize',
            'type': 'x',
            'photo': _tdFile(f),
            'width': 0,
            'height': 0,
            'progressive_sizes': const <int>[],
          },
        ],
      };
    }
    return {
      '@type': 'linkPreview',
      'url': url,
      'display_url': url,
      'site_name': raw['site_name'] ?? '',
      'title': raw['title'] ?? '',
      'description': _formatted(raw['description']?.toString() ?? ''),
      'author': '',
      'type': {
        '@type': 'linkPreviewTypeArticle',
        'has_large_media': image.isNotEmpty,
        'photo': photo,
      },
      'has_large_media': false,
      'show_large_media': false,
      'show_media_above_description': false,
      'skip_confirmation': true,
      'show_above_text': false,
      'instant_view_version': 0,
      '@ql_preview_id': raw['id'],
    };
  }

  // MARK: Stories / moments

  int _storyPosterChatId(String authorId) => qlUserInt(authorId);

  String? _authorFromPosterChat(int chatId) {
    if (chatId == _myInt) return _myId;
    final c = _conv(chatId);
    if (c != null && !c.isGroup) return c.peerId;
    return _userIdByInt[chatId];
  }

  Map<String, dynamic> _tdStory(Map raw, {required String viewer}) {
    final author = raw['author_id']?.toString() ?? '';
    final no = QlTdEngine._int(raw['story_no']) ?? 0;
    final mediaId = raw['media_id']?.toString() ?? '';
    final kind = raw['kind']?.toString() ?? 'photo';
    final file = _fileForMedia(mediaId, kind: kind == 'video' ? 'video' : 'image');
    final content = kind == 'video'
        ? {
            '@type': 'storyContentVideo',
            'video': {
              '@type': 'storyVideo',
              'duration': 0.0,
              'width': 0,
              'height': 0,
              'has_stickers': false,
              'is_animation': false,
              'minithumbnail': null,
              'thumbnail': null,
              'preload_prefix_size': 0,
              'cover_frame_timestamp': 0.0,
              'video': file,
            },
          }
        : {
            '@type': 'storyContentPhoto',
            'photo': {
              '@type': 'photo',
              'has_stickers': false,
              'minithumbnail': null,
              'sizes': [
                {
                  '@type': 'photoSize',
                  'type': 'x',
                  'photo': file,
                  'width': 0,
                  'height': 0,
                  'progressive_sizes': const <int>[],
                },
              ],
            },
          };
    final privacy = raw['privacy'] is Map ? Map<String, dynamic>.from(raw['privacy'] as Map) : const <String, dynamic>{};
    final chosen = raw['chosen_reaction']?.toString();
    return {
      '@type': 'story',
      'id': no,
      'poster_chat_id': _storyPosterChatId(author),
      'publisher_chat_id': 0,
      'date': QlTdEngine._int(raw['created']) ?? 0,
      'is_being_sent': false,
      'is_being_edited': false,
      'is_edited': false,
      'is_posted_to_chat_page': raw['posted_to_page'] != false,
      'is_visible_only_for_self': false,
      'can_be_deleted': raw['can_delete'] == true,
      'can_be_edited': raw['can_edit'] == true,
      'can_be_forwarded': true,
      'can_be_replied': author != viewer,
      'can_toggle_is_posted_to_chat_page': raw['can_edit'] == true,
      'can_get_interactions': raw['can_get_interactions'] == true,
      'can_get_statistics': false,
      'has_expired_viewers': false,
      'repost_info': null,
      'interaction_info': {
        '@type': 'storyInteractionInfo',
        'view_count': QlTdEngine._int(raw['view_count']) ?? 0,
        'forward_count': 0,
        'reaction_count': QlTdEngine._int(raw['reaction_count']) ?? 0,
        'recent_viewer_user_ids': [
          for (final id in (raw['recent_viewer_ids'] as List? ?? const [])) qlUserInt(id.toString()),
        ],
      },
      'chosen_reaction_type': chosen == null || chosen.isEmpty ? null : {'@type': 'reactionTypeEmoji', 'emoji': chosen},
      'privacy_settings': _tdStoryPrivacy(privacy),
      'content': content,
      'areas': raw['areas'] is List ? raw['areas'] : const <Object>[],
      'caption': _formatted(raw['caption']?.toString() ?? '', _tdEntities(raw['caption']?.toString() ?? '', raw['entities'])),
    };
  }

  Map<String, dynamic> _tdStoryPrivacy(Map privacy) {
    switch (privacy['type']) {
      case 'contacts':
        return {'@type': 'storyPrivacySettingsContacts'};
      case 'close_friends':
        return {'@type': 'storyPrivacySettingsCloseFriends'};
      case 'users':
        return {
          '@type': 'storyPrivacySettingsSelectedUsers',
          'user_ids': [
            for (final id in (privacy['user_ids'] as List? ?? const [])) qlUserInt(id.toString()),
          ],
        };
      default:
        return {'@type': 'storyPrivacySettingsEveryone'};
    }
  }

  Map<String, dynamic> _privacyFromTd(Object? settings) {
    if (settings is! Map) return {'type': 'everyone'};
    switch (settings['@type']) {
      case 'storyPrivacySettingsContacts':
        return {'type': 'contacts'};
      case 'storyPrivacySettingsCloseFriends':
        return {'type': 'close_friends'};
      case 'storyPrivacySettingsSelectedUsers':
        return {
          'type': 'users',
          'user_ids': [
            for (final v in (settings['user_ids'] as List? ?? const []))
              if (_userIdByInt[QlTdEngine._int(v) ?? 0] != null) _userIdByInt[QlTdEngine._int(v) ?? 0],
          ],
        };
      default:
        return {'type': 'everyone'};
    }
  }

  Future<String?> _uploadStoryMedia(Map content) async {
    final typ = content['@type']?.toString() ?? '';
    String? path;
    if (typ == 'inputStoryContentPhoto') {
      path = _inputFilePath(content['photo'] is Map ? (content['photo'] as Map)['photo'] ?? content['photo'] : content['photo']);
    } else if (typ == 'inputStoryContentVideo') {
      path = _inputFilePath(content['video'] is Map ? (content['video'] as Map)['video'] ?? content['video'] : content['video']);
    }
    if (path == null) return null;
    final uploaded = await _apiOrThrow.uploadFile(
      path,
      mimeType: uploadMimeForPath(path),
    );
    return uploaded['id']?.toString();
  }

  Future<Map<String, dynamic>> _postStory(Map<String, dynamic> r) async {
    final chatId = QlTdEngine._int(r['chat_id']) ?? 0;
    if (chatId != _myInt && _authorFromPosterChat(chatId) != _myId) {
      return _error(400, '只能给自己发布动态');
    }
    final content = r['content'] is Map ? Map<String, dynamic>.from(r['content'] as Map) : <String, dynamic>{};
    final mediaId = await _uploadStoryMedia(content);
    if (mediaId == null || mediaId.isEmpty) return _error(400, '需要照片或视频');
    final kind = content['@type'] == 'inputStoryContentVideo' ? 'video' : 'photo';
    final caption = r['caption'] is Map ? r['caption']['text']?.toString() ?? '' : r['caption']?.toString() ?? '';
    final raw = await _apiOrThrow.post('/stories', {
      'media_id': mediaId,
      'kind': kind,
      'caption': caption,
      'entities': _backendEntities(r['caption'] is Map ? Map<String, dynamic>.from(r['caption'] as Map) : null),
      'privacy': _privacyFromTd(r['privacy_settings']),
      'posted_to_page': r['is_posted_to_chat_page'] != false,
    });
    final story = _tdStory(raw, viewer: _myId);
    _emit({'@type': 'updateStory', 'story': story});
    await _emitOwnActiveStories();
    return story;
  }

  Future<Map<String, dynamic>> _editStoryTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0) ?? _myId;
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    final body = <String, dynamic>{};
    if (r['caption'] != null) {
      final caption = r['caption'] is Map ? r['caption']['text']?.toString() ?? '' : r['caption']?.toString() ?? '';
      body['caption'] = caption;
      body['entities'] = _backendEntities(r['caption'] is Map ? Map<String, dynamic>.from(r['caption'] as Map) : null);
    }
    if (r['areas'] != null) body['areas'] = r['areas'];
    final raw = await _apiOrThrow.patch('/stories/$author/$no', body);
    final story = _tdStory(raw, viewer: _myId);
    _emit({'@type': 'updateStory', 'story': story});
    return story;
  }

  Future<Map<String, dynamic>> _deleteStoryTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0) ?? _myId;
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    await _apiOrThrow.delete('/stories/$author/$no');
    _emit({
      '@type': 'updateChatActiveStories',
      'active_stories': await _activeStoriesFor(author),
    });
    return _ok;
  }

  Future<Map<String, dynamic>> _getStoryTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0);
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    if (author == null || no <= 0) return _error(400, 'Story not found');
    final raw = await _apiOrThrow.get('/stories/$author/$no');
    return _tdStory(raw, viewer: _myId);
  }

  Future<Map<String, dynamic>> _openStoryTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0);
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    if (author == null || no <= 0) return _error(400, 'Story not found');
    await _apiOrThrow.post('/stories/$author/$no/open');
    return _ok;
  }

  Future<Map<String, dynamic>> _activeStoriesFor(String author) async {
    final raw = await _apiOrThrow.get('/users/$author/stories');
    final stories = raw['stories'] is List ? raw['stories'] as List : const [];
    var maxRead = 0;
    try {
      final active = await _apiOrThrow.get('/stories/active');
      for (final c in (active['chats'] as List? ?? const [])) {
        if (c is Map && c['author_id'] == author) {
          maxRead = QlTdEngine._int(c['max_read_story_no']) ?? 0;
        }
      }
    } catch (_) {}
    final infos = [
      for (final s in stories)
        if (s is Map)
          {
            '@type': 'storyInfo',
            'story_id': QlTdEngine._int(s['story_no']) ?? 0,
            'date': QlTdEngine._int(s['created']) ?? 0,
            'is_live': false,
            'is_for_close_friends': (s['privacy'] is Map && s['privacy']['type'] == 'close_friends'),
          },
    ];
    final newest = infos.isEmpty ? 0 : (infos.first['date'] as int);
    return {
      '@type': 'chatActiveStories',
      'chat_id': _storyPosterChatId(author),
      'list': {'@type': 'storyListMain'},
      'order': newest,
      'max_read_story_id': maxRead,
      'stories': infos,
    };
  }

  Future<Map<String, dynamic>> _loadActiveStories(Map<String, dynamic> r) async {
    if (_activeStoriesLoaded) return _error(404, 'Not Found');
    final raw = await _apiOrThrow.get('/stories/active');
    for (final c in (raw['chats'] as List? ?? const [])) {
      if (c is! Map) continue;
      final author = c['author_id']?.toString() ?? '';
      if (author.isEmpty) continue;
      try {
        await _ensureUser(author);
      } catch (_) {}
      // Ensure a private chat exists so Moments can resolve the title/photo.
      try {
        await _createPrivateChat(qlUserInt(author));
      } catch (_) {}
      final stories = c['stories'] is List ? c['stories'] as List : const [];
      final infos = [
        for (final s in stories)
          if (s is Map)
            {
              '@type': 'storyInfo',
              'story_id': QlTdEngine._int(s['story_no']) ?? 0,
              'date': QlTdEngine._int(s['created']) ?? 0,
              'is_live': false,
              'is_for_close_friends': false,
            },
      ];
      final newest = infos.isEmpty ? 0 : infos.map((e) => e['date'] as int).fold(0, math.max);
      _emit({
        '@type': 'updateChatActiveStories',
        'active_stories': {
          '@type': 'chatActiveStories',
          'chat_id': _storyPosterChatId(author),
          'list': r['story_list'] ?? {'@type': 'storyListMain'},
          'order': newest,
          'max_read_story_id': QlTdEngine._int(c['max_read_story_no']) ?? 0,
          'stories': infos,
        },
      });
    }
    _activeStoriesLoaded = true;
    return _ok;
  }

  Future<Map<String, dynamic>> _chatActiveStories(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['chat_id']) ?? 0);
    if (author == null) return _error(404, 'Not Found');
    return {'@type': 'chatActiveStories', ...(await _activeStoriesFor(author))};
  }

  Future<Map<String, dynamic>> _chatsToPostStories() async {
    await _createPrivateChat(_myInt);
    return {'@type': 'chats', 'total_count': 1, 'chat_ids': [_myInt]};
  }

  Future<Map<String, dynamic>> _canPostStory(Map<String, dynamic> r) async {
    final chatId = QlTdEngine._int(r['chat_id']) ?? 0;
    if (chatId == _myInt || _authorFromPosterChat(chatId) == _myId) {
      return {'@type': 'canPostStoryResultOk', 'story_count': 0, 'monthly_count': 0, 'weekly_count': 0};
    }
    return {'@type': 'canPostStoryResultPremiumNeeded'};
  }

  Future<void> _emitOwnActiveStories() async {
    _emit({'@type': 'updateChatActiveStories', 'active_stories': await _activeStoriesFor(_myId)});
  }

  Future<Map<String, dynamic>> _setStoryPrivacyTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0) ?? _myId;
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    final raw = await _apiOrThrow.put('/stories/$author/$no/privacy', _privacyFromTd(r['privacy_settings']));
    final story = _tdStory(raw, viewer: _myId);
    _emit({'@type': 'updateStory', 'story': story});
    return _ok;
  }

  Future<Map<String, dynamic>> _setStoryReactionTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0);
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    if (author == null) return _error(400, 'Story not found');
    final typ = r['reaction_type'];
    final emoji = typ is Map ? typ['emoji']?.toString() ?? '' : '';
    final isChosen = r['is_chosen'] != false;
    await _apiOrThrow.put('/stories/$author/$no/reaction', {'emoji': emoji, 'remove': !isChosen || emoji.isEmpty});
    return _ok;
  }

  Future<Map<String, dynamic>> _storyInteractionsTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0);
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    if (author == null) return _error(400, 'Story not found');
    final raw = await _apiOrThrow.get('/stories/$author/$no/interactions');
    return {
      '@type': 'storyInteractions',
      'total_count': (raw['interactions'] as List? ?? const []).length,
      'total_forward_count': 0,
      'total_reaction_count': 0,
      'interactions': [
        for (final i in (raw['interactions'] as List? ?? const []))
          if (i is Map)
            {
              '@type': 'storyInteraction',
              'actor_id': {'@type': 'messageSenderUser', 'user_id': qlUserInt(i['user_id']?.toString() ?? '')},
              'interaction_date': QlTdEngine._int(i['viewed_at']) ?? 0,
              'type': (i['emoji']?.toString() ?? '').isEmpty
                  ? {'@type': 'storyInteractionTypeView', 'chosen_reaction_type': null}
                  : {
                      '@type': 'storyInteractionTypeView',
                      'chosen_reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': i['emoji']},
                    },
            },
      ],
    };
  }

  Future<Map<String, dynamic>> _reportStoryTd(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0);
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    if (author == null) return _error(400, 'Story not found');
    await _apiOrThrow.post('/stories/$author/$no/report', {'reason': r['reason']?['@type'] ?? 'other'});
    return _ok;
  }

  Future<Map<String, dynamic>> _toggleStoryPage(Map<String, dynamic> r) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['story_poster_chat_id']) ?? 0) ?? _myId;
    final no = QlTdEngine._int(r['story_id']) ?? 0;
    await _apiOrThrow.patch('/stories/$author/$no', {'posted_to_page': r['is_posted_to_chat_page'] == true});
    return _ok;
  }

  Future<Map<String, dynamic>> _listUserStoriesTd(Map<String, dynamic> r, {required bool archived}) async {
    final author = _authorFromPosterChat(QlTdEngine._int(r['chat_id']) ?? 0);
    if (author == null) return {'@type': 'stories', 'total_count': 0, 'stories': const <Object>[], 'pinned_story_ids': const <int>[]};
    final from = QlTdEngine._int(r['from_story_id']) ?? 0;
    final limit = QlTdEngine._int(r['limit']) ?? 50;
    final raw = await _apiOrThrow.get('/users/$author/stories', {
      'archived': archived ? '1' : '0',
      if (from > 0) 'from_no': '$from',
      'limit': '$limit',
    });
    final stories = [
      for (final s in (raw['stories'] as List? ?? const []))
        if (s is Map) _tdStory(s, viewer: _myId),
    ];
    return {'@type': 'stories', 'total_count': stories.length, 'stories': stories, 'pinned_story_ids': const <int>[]};
  }

  void _onStoryEvent(String type, Map<String, dynamic> data) {
    final author = data['author_id']?.toString() ?? '';
    if (author.isEmpty) return;
    if (type == 'story.deleted') {
      unawaited(() async {
        try {
          _emit({'@type': 'updateChatActiveStories', 'active_stories': await _activeStoriesFor(author)});
        } catch (_) {}
      }());
      return;
    }
    _emit({'@type': 'updateStory', 'story': _tdStory(data, viewer: _myId)});
    unawaited(() async {
      try {
        _emit({'@type': 'updateChatActiveStories', 'active_stories': await _activeStoriesFor(author)});
      } catch (_) {}
    }());
  }

    // MARK: - Sticker set editing

  /// Resolves the string sticker id behind a TDLib `file_id` within a pack.
  ///
  /// qlPackInt hashes the id, so the mapping is not reversible: the pack is
  /// listed and matched instead. Returns null when the sticker is not in it.
  Future<({String packId, String stickerId})?> _stickerRef(
    String packName,
    int stickerIntId,
  ) async {
    final packId = await _packIdByName(packName);
    if (packId == null) return null;
    final detail = await _apiOrThrow.get('/sticker-packs/$packId');
    for (final raw in (detail['stickers'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final sid = raw['id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      if (qlPackInt('sticker:$sid') == stickerIntId) {
        return (packId: packId, stickerId: sid);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _deleteStickerSet(Map<String, dynamic> r) async {
    final packId = await _packIdByName(r['name']?.toString() ?? '');
    if (packId == null) return _error(404, 'Sticker set not found');
    await _apiOrThrow.delete('/sticker-packs/$packId');
    return {'@type': 'ok'};
  }

  Future<Map<String, dynamic>> _setStickerSetTitle(
    Map<String, dynamic> r,
  ) async {
    final title = (r['title']?.toString() ?? '').trim();
    if (title.isEmpty || title.length > 100) return _error(400, 'TITLE_INVALID');
    final packId = await _packIdByName(r['name']?.toString() ?? '');
    if (packId == null) return _error(404, 'Sticker set not found');
    await _apiOrThrow.patch('/sticker-packs/$packId', {'title': title});
    return {'@type': 'ok'};
  }

  Future<Map<String, dynamic>> _removeStickerFromSet(
    Map<String, dynamic> r,
  ) async {
    final name = r['name']?.toString() ?? '';
    final fileId = QlTdEngine._int(_inputFileId(r['sticker'])) ?? 0;
    final ref = await _stickerRef(name, fileId);
    if (ref == null) return _error(404, 'Sticker not found');
    await _apiOrThrow.delete(
      '/sticker-packs/${ref.packId}/stickers/${ref.stickerId}',
    );
    return {'@type': 'ok'};
  }

  Future<Map<String, dynamic>> _setStickerPositionInSet(
    Map<String, dynamic> r,
  ) async {
    final name = r['name']?.toString() ?? '';
    final fileId = QlTdEngine._int(_inputFileId(r['sticker'])) ?? 0;
    final position = QlTdEngine._int(r['position']) ?? 0;
    final ref = await _stickerRef(name, fileId);
    if (ref == null) return _error(404, 'Sticker not found');
    await _apiOrThrow.patch(
      '/sticker-packs/${ref.packId}/stickers/${ref.stickerId}',
      {'position': position},
    );
    return {'@type': 'ok'};
  }

  /// 轻聊 derives a pack's cover from its first sticker, so pointing the
  /// thumbnail at one of the pack's own stickers needs no server call: the
  /// choice is already reflected by reordering. An uploaded thumbnail image
  /// has nowhere to be stored, so it is refused rather than silently dropped.
  Future<Map<String, dynamic>> _setStickerSetThumbnail(
    Map<String, dynamic> r,
  ) async {
    final thumb = r['thumbnail'];
    if (thumb is Map && thumb['@type'] == 'inputFileId') {
      return {'@type': 'ok'};
    }
    return _unsupported('setStickerSetThumbnail(uploaded image)');
  }

  /// TDLib sends either an inputFileId wrapper or a bare id.
  Object? _inputFileId(Object? sticker) {
    if (sticker is Map) return sticker['id'];
    return sticker;
  }

  /// 轻聊 exposes every pack to every member, so there is no per-user install
  /// list to write. The call succeeds so the UI's toggle reflects its own
  /// choice; nothing is persisted because nothing needs to be.
  Future<Map<String, dynamic>> _changeStickerSet(Map<String, dynamic> r) async {
    final packId = await _packIdByName(
      (QlTdEngine._int(r['set_id']) ?? 0).toString(),
    );
    if (packId == null) return _error(404, 'Sticker set not found');
    return {'@type': 'ok'};
  }

  Future<void> _ensureChatMeta(_Conv c) async {
    if (c.metaLoaded || c.id.startsWith('virtual:')) return;
    c.metaLoaded = true;
    try {
      final raw = await _apiOrThrow.get('/conversations/${c.id}');
      c.description = raw['description']?.toString() ?? '';
      c.slowMode = QlTdEngine._int(raw['slow_mode_seconds']) ?? 0;
      c.autoDelete = QlTdEngine._int(raw['auto_delete_seconds']) ?? 0;
      c.historyForNew = raw['history_for_new'] == true;
      c.upgraded = raw['upgraded'] == true;
      c.username = raw['username']?.toString() ?? c.username;
      c.protectedContent = raw['protected'] == true;
      c.joinByRequest = raw['join_by_request'] == true;
      c.pendingJoins = QlTdEngine._int(raw['pending_join_requests']) ?? c.pendingJoins;
      final perms = raw['permissions'];
      if (perms is Map) c.permissions = Map<String, dynamic>.from(perms);
    } catch (_) {}
    if (!c.isGroup || (c.role != 'owner' && c.role != 'admin')) return;
    try {
      final links = await _apiOrThrow.get('/conversations/${c.id}/invites');
      final list = links['invites'];
      if (list is List && list.isNotEmpty && list.first is Map) {
        c.inviteLink = _tdInviteLink(Map<String, dynamic>.from(list.first as Map));
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _transferChatOwnership(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final userId = _userIdByInt[QlTdEngine._int(r['user_id']) ?? 0];
    final password = r['password']?.toString() ?? '';
    if (c == null || userId == null || password.isEmpty) return _error(400, 'PASSWORD_HASH_INVALID');
    try {
      await _apiOrThrow.post('/conversations/${c.id}/transfer', {'user_id': userId, 'password': password});
    } on QlApiException catch (e) {
      return _error(_tdCode(e.statusCode), e.statusCode == 403 ? 'PASSWORD_HASH_INVALID' : e.error);
    }
    c.role = 'admin';
    for (final m in c.members) {
      if (m['user_id'] == userId) m['role'] = 'owner';
      if (m['user_id'] == _myId) m['role'] = 'admin';
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _upgradeBasicGroup(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || c.kind != 'group') return _error(400, 'Chat not found');
    final raw = await _apiOrThrow.post('/conversations/${c.id}/upgrade', {});
    c.upgraded = raw['upgraded'] == true;
    c.metaLoaded = true;
    final chat = _tdChat(c);
    if (c.announced) _emit({'@type': 'updateChat', 'chat': chat});
    return chat;
  }

  Future<Map<String, dynamic>> _setAutoDelete(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final nested = r['message_auto_delete_time'];
    final seconds = nested is Map ? (QlTdEngine._int(nested['time']) ?? 0) : (QlTdEngine._int(r['message_auto_delete_time']) ?? 0);
    await _apiOrThrow.put('/conversations/${c.id}/auto-delete', {'seconds': seconds});
    c.autoDelete = seconds;
    if (c.announced) {
      _emit({
        '@type': 'updateChatMessageAutoDeleteTime',
        'chat_id': c.chatId,
        'message_auto_delete_time': {'@type': 'messageAutoDeleteTime', 'time': seconds},
      });
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _toggleHistory(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['supergroup_id']) ?? 0;
    _Conv? found;
    for (final c in _convs.values) {
      if ((c.isChannel || c.upgraded) && qlGroupInt(c.id) == id) found = c;
    }
    if (found == null) return _error(404, 'Supergroup not found');
    final on = r['is_all_history_available'] == true;
    await _apiOrThrow.put('/conversations/${found.id}/history', {'history_for_new': on});
    found.historyForNew = on;
    return _ok;
  }

  Future<Map<String, dynamic>> _messageReadDate(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final seq = qlSeqOf(QlTdEngine._int(r['message_id']) ?? 0);
    if (c == null || seq <= 0) return _error(404, 'Not Found');
    return _apiOrThrow.get('/conversations/${c.id}/messages/$seq/read-date');
  }

  Future<Map<String, dynamic>> _messageViewers(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final seq = qlSeqOf(QlTdEngine._int(r['message_id']) ?? 0);
    if (c == null || seq <= 0) return _error(404, 'Not Found');
    final raw = await _apiOrThrow.get('/conversations/${c.id}/messages/$seq/viewers');
    final viewers = <Map<String, dynamic>>[];
    for (final item in (raw['viewers'] as List? ?? const [])) {
      if (item is! Map) continue;
      final uid = item['user_id']?.toString() ?? '';
      if (uid.isNotEmpty && !_users.containsKey(uid)) {
        try {
          await _ensureUser(uid);
        } catch (_) {}
      }
      viewers.add({
        '@type': 'messageViewer',
        'user_id': qlUserInt(uid),
        'view_date': QlTdEngine._int(item['view_date']) ?? 0,
      });
    }
    return {'@type': 'messageViewers', 'viewers': viewers};
  }

  Future<Map<String, dynamic>> _customEmojiStickers(Map<String, dynamic> r) async {
    final wanted = <int>{
      for (final v in (r['custom_emoji_ids'] as List? ?? const []))
        if (QlTdEngine._int(v) != null) QlTdEngine._int(v)!,
    };
    final raw = await _apiOrThrow.get('/custom-emoji');
    final stickers = <Map<String, dynamic>>[];
    for (final item in (raw['stickers'] as List? ?? const [])) {
      if (item is! Map) continue;
      final sticker = _tdSticker(Map<String, dynamic>.from(item), emoji: true);
      final id = QlTdEngine._int((sticker['full_type'] as Map)['custom_emoji_id']) ?? 0;
      if (wanted.isEmpty || wanted.contains(id)) stickers.add(sticker);
    }
    return {'@type': 'stickers', 'stickers': stickers};
  }

  Future<Map<String, dynamic>> _scheduledMessages(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (c.id.startsWith('virtual:')) {
      return {'@type': 'messages', 'total_count': 0, 'messages': const <Object>[]};
    }
    final raw = await _apiOrThrow.get('/conversations/${c.id}/scheduled');
    final messages = <Map<String, dynamic>>[];
    for (final item in (raw['messages'] as List? ?? const [])) {
      if (item is! Map) continue;
      final td = _tdMessage(c, Map<String, dynamic>.from(item));
      if (td != null) messages.add(td);
    }
    c.hasScheduled = messages.isNotEmpty;
    return {'@type': 'messages', 'total_count': messages.length, 'messages': messages};
  }

  _Conv? _convBySupergroup(int id) {
    for (final c in _convs.values) {
      if ((c.isChannel || c.upgraded) && qlGroupInt(c.id) == id) return c;
    }
    return null;
  }

  Future<Map<String, dynamic>> _setSupergroupUsername(Map<String, dynamic> r) async {
    final c = _convBySupergroup(QlTdEngine._int(r['supergroup_id']) ?? 0);
    if (c == null) return _error(404, 'Supergroup not found');
    final name = (r['username']?.toString() ?? '').trim();
    try {
      final raw = await _apiOrThrow.put('/conversations/${c.id}/username', {'username': name});
      c.username = raw['username']?.toString() ?? '';
    } on QlApiException catch (e) {
      return _error(_tdCode(e.statusCode), e.statusCode == 409 ? 'USERNAME_NOT_MODIFIED' : e.error);
    }
    if (c.announced) {
      _emit({'@type': 'updateChat', 'chat': _tdChat(c)});
      _emit({'@type': 'updateSupergroup', 'supergroup': _supergroup(c)});
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _setProtected(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    final enabled = r['has_protected_content'] == true;
    await _apiOrThrow.put('/conversations/${c.id}/protected', {'enabled': enabled});
    c.protectedContent = enabled;
    if (c.announced) _emit({'@type': 'updateChat', 'chat': _tdChat(c)});
    return _ok;
  }

  Future<Map<String, dynamic>> _setJoinByRequest(Map<String, dynamic> r) async {
    final c = _convBySupergroup(QlTdEngine._int(r['supergroup_id']) ?? 0);
    if (c == null) return _error(404, 'Supergroup not found');
    final enabled = r['join_by_request'] == true;
    await _apiOrThrow.put('/conversations/${c.id}/join-by-request', {
      'enabled': enabled,
      'apply_to_invite_links': r['apply_to_invite_links'] == true,
    });
    c.joinByRequest = enabled;
    if (c.announced) {
      _emit({'@type': 'updateChat', 'chat': _tdChat(c)});
      _emit({'@type': 'updateSupergroup', 'supergroup': _supergroup(c)});
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _joinRequests(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final limit = (QlTdEngine._int(r['limit']) ?? 100).clamp(1, 100);
    final raw = await _apiOrThrow.get('/conversations/${c.id}/join-requests');
    final all = <Map<String, dynamic>>[];
    for (final item in (raw['requests'] as List? ?? const [])) {
      if (item is! Map) continue;
      final uid = item['user_id']?.toString() ?? '';
      all.add({
        '@type': 'chatJoinRequest',
        'chat_id': c.chatId,
        'user_id': qlUserInt(uid),
        'date': QlTdEngine._int(item['date']) ?? 0,
        'bio': '',
      });
    }
    var start = 0;
    final offset = r['offset_request'];
    if (offset is Map) {
      final uid = QlTdEngine._int(offset['user_id']) ?? 0;
      final date = QlTdEngine._int(offset['date']) ?? 0;
      final at = all.indexWhere((q) => q['user_id'] == uid && q['date'] == date);
      if (at >= 0) start = at + 1;
    }
    final page = all.skip(start).take(limit).toList();
    return {'@type': 'chatJoinRequests', 'total_count': all.length, 'requests': page};
  }

  Future<Map<String, dynamic>> _processJoinRequest(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final uid = _userIdByInt[QlTdEngine._int(r['user_id']) ?? 0];
    if (c == null || uid == null) return _error(400, 'Chat or user not found');
    await _apiOrThrow.post('/conversations/${c.id}/join-requests/$uid', {'approve': r['approve'] == true});
    return _ok;
  }

  Future<Map<String, dynamic>> _processJoinRequests(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    await _apiOrThrow.post('/conversations/${c.id}/join-requests', {'approve': r['approve'] == true});
    return _ok;
  }

  Future<Map<String, dynamic>> _messageLink(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final seq = qlSeqOf(id);
    if (c == null || seq <= 0) return _error(400, 'Message not found');
    final public = c.username.isNotEmpty;
    final link = public ? 'https://t.me/${c.username}/$seq' : 'mk://msg?chat=${c.chatId}&message=$id';
    return {'@type': 'messageLink', 'link': link, 'is_public': public};
  }

  Map<String, dynamic>? _classifyLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if (scheme == 'tg' && host == 'msg') {
      return {'@type': 'internalLinkTypeMessage', 'url': link};
    }
    if (scheme == 'tg' && host == 'resolve') {
      final domain = uri.queryParameters['domain'] ?? '';
      if (domain.isEmpty) return null;
      final post = uri.queryParameters['post'];
      if (post != null && post.isNotEmpty) {
        return {'@type': 'internalLinkTypeMessage', 'url': link};
      }
      return {'@type': 'internalLinkTypePublicChat', 'chat_username': domain};
    }
    if (host == 't.me' || host == 'telegram.me' || host == 'www.t.me' || host == 'www.telegram.me') {
      final segs = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
      if (segs.isEmpty) return null;
      const reserved = {'share', 'addstickers', 'login', 'proxy', 'joinchat', 'iv', 'bg', 'socks', 'addtheme', 'confirmphone'};
      if (reserved.contains(segs.first.toLowerCase()) || segs.first.startsWith('+')) return null;
      if (segs.length >= 2 && int.tryParse(segs[1]) != null) {
        return {'@type': 'internalLinkTypeMessage', 'url': link};
      }
      if (RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(segs.first)) {
        return {'@type': 'internalLinkTypePublicChat', 'chat_username': segs.first};
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _messageLinkInfo(Map<String, dynamic> r) async {
    final url = r['url']?.toString() ?? '';
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return _error(400, 'LINK_INVALID');
    int? chatId;
    int? messageId;
    var isPublic = false;
    final host = uri.host.toLowerCase();
    if (uri.scheme.toLowerCase() == 'tg' && host == 'msg') {
      chatId = int.tryParse(uri.queryParameters['chat'] ?? '');
      messageId = int.tryParse(uri.queryParameters['message'] ?? '');
    } else if (uri.scheme.toLowerCase() == 'tg' && host == 'resolve') {
      final domain = uri.queryParameters['domain'] ?? '';
      final post = int.tryParse(uri.queryParameters['post'] ?? '');
      if (domain.isNotEmpty && post != null) {
        final chat = await _searchPublicChat(domain);
        if (chat['@type'] != 'chat') return chat;
        chatId = QlTdEngine._int(chat['id']);
        messageId = qlMessageId(post);
        isPublic = true;
      }
    } else if (host == 't.me' || host == 'telegram.me' || host == 'www.t.me' || host == 'www.telegram.me') {
      final segs = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
      if (segs.length >= 2 && segs.first != 'c') {
        final seq = int.tryParse(segs[1]);
        if (seq != null) {
          final chat = await _searchPublicChat(segs.first);
          if (chat['@type'] != 'chat') return chat;
          chatId = QlTdEngine._int(chat['id']);
          messageId = qlMessageId(seq);
          isPublic = true;
        }
      }
    }
    if (chatId == null || messageId == null) return _error(400, 'LINK_INVALID');
    final message = await _getMessage(chatId, messageId);
    if (message['@type'] != 'message') return message;
    return {
      '@type': 'messageLinkInfo',
      'is_public': isPublic,
      'chat_id': chatId,
      'message': message,
      'media_timestamp': 0,
      'for_album': false,
    };
  }

  Future<Map<String, dynamic>> _messageByDate(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final at = QlTdEngine._int(r['date']) ?? 0;
    if (c == null || at <= 0) return _error(400, 'Chat not found');
    final raw = await _apiOrThrow.get('/conversations/${c.id}/by-date', {'at': '$at'});
    final td = _tdMessage(c, Map<String, dynamic>.from(raw));
    if (td == null) return _error(404, 'Not Found');
    _cacheMessage(c, td, Map<String, dynamic>.from(raw));
    return td;
  }

  Future<Map<String, dynamic>> _pollVoters(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final messageId = QlTdEngine._int(r['message_id']) ?? 0;
    if (c == null) return _error(400, 'Chat not found');
    var td = c.messages[qlSeqOf(messageId)];
    td ??= await _getMessage(c.chatId, messageId);
    final pollId = ((td['content'] as Map?)?['@ql_poll_id'])?.toString() ?? '';
    if (pollId.isEmpty) return _error(400, 'Poll not found');
    final raw = await _apiOrThrow.get('/conversations/${c.id}/polls/$pollId/voters', {
      'option_id': '${QlTdEngine._int(r['option_id']) ?? 0}',
      'offset': '${QlTdEngine._int(r['offset']) ?? 0}',
      'limit': '${QlTdEngine._int(r['limit']) ?? 50}',
    });
    final voters = <Map<String, dynamic>>[];
    for (final item in (raw['voters'] as List? ?? const [])) {
      if (item is! Map) continue;
      final uid = item['user_id']?.toString() ?? '';
      if (uid.isNotEmpty) {
        try {
          await _ensureUser(uid);
        } catch (_) {}
      }
      voters.add({'@type': 'messageSenderUser', 'user_id': qlUserInt(uid)});
    }
    return {
      '@type': 'messageSenders',
      'total_count': QlTdEngine._int(raw['total_count']) ?? voters.length,
      'senders': voters,
      'voters': voters,
    };
  }

  Future<Map<String, dynamic>> _editScheduling(Map<String, dynamic> r) async {
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    final sid = _scheduledBackend[id];
    if (sid == null || sid.isEmpty) return _error(404, 'Message not found');
    final state = r['scheduling_state'];
    if (state == null) {
      await _apiOrThrow.post('/scheduled/$sid/send', {});
    } else if (state is Map && state['@type'] == 'messageSchedulingStateSendWhenOnline') {
      await _apiOrThrow.patch('/scheduled/$sid', {'when_online': true, 'send_at': 0});
    } else if (state is Map) {
      await _apiOrThrow.patch('/scheduled/$sid', {
        'when_online': false,
        'send_at': QlTdEngine._int(state['send_date']) ?? 0,
      });
    } else {
      return _error(400, 'SCHEDULING_STATE_INVALID');
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _editMedia(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final id = QlTdEngine._int(r['message_id']) ?? 0;
    if (c == null) return _error(400, 'Chat not found');
    final backendId = c.messages[qlSeqOf(id)]?['@ql_id']?.toString() ?? '';
    final input = r['input_message_content'];
    if (backendId.isEmpty || input is! Map) return _error(400, 'Message not found');
    final draft = _draftContent(Map<String, dynamic>.from(input));
    if (draft == null || draft.path == null) return _unsupported('editMessageMedia');
    final headers = await _uploadHeadersFor(draft.kind, draft.path!, draft.content);
    final uploaded = await _apiOrThrow.uploadFile(
      draft.path!,
      conversationId: c.id,
      mimeType: _uploadMimeFor(draft.kind, draft.path!),
      headers: headers,
    );
    final mediaId = uploaded['id']?.toString() ?? '';
    if (mediaId.isEmpty) return _error(500, 'upload_failed');
    final result = await _apiOrThrow.patch('/messages/$backendId/media', {
      'kind': draft.kind,
      'text': draft.text,
      'media_id': mediaId,
      if (draft.entities.isNotEmpty) 'entities': draft.entities,
      if (draft.extra != null) 'extra': draft.extra,
    });
    final td = _tdMessage(c, result);
    if (td == null) return _error(400, 'Message was deleted');
    await _onMessageEdited(c.id, result);
    return td;
  }

  Future<Map<String, dynamic>> _deleteChat(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    if (!c.id.startsWith('virtual:')) {
      await _apiOrThrow.delete('/conversations/${c.id}');
    }
    if (c.announced) {
      _emit({
        '@type': 'updateChatPosition',
        'chat_id': c.chatId,
        'position': _position(c, removed: true),
      });
    }
    _convByChatId.remove(c.chatId);
    _convs.remove(c.id);
    return _ok;
  }

  Future<Map<String, dynamic>> _setBio(Map<String, dynamic> r) async {
    final bio = r['bio']?.toString() ?? '';
    if (bio.runes.length > 70) return _error(400, 'BIO_TOO_LONG');
    return _patchMe(bio: bio);
  }

  Future<Map<String, dynamic>> _setUsername(Map<String, dynamic> r) async {
    final username = (r['username']?.toString() ?? '').trim();
    if (username.isEmpty) return _error(400, 'USERNAME_INVALID');
    return _patchMe(username: username);
  }

  Future<Map<String, dynamic>> _setChatDescription(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final description = (r['description']?.toString() ?? '').trim();
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    if (description.runes.length > 255) return _error(400, 'DESCRIPTION_TOO_LONG');
    await _apiOrThrow.patch('/conversations/${c.id}', {'description': description});
    c.description = description;
    c.metaLoaded = true;
    return _ok;
  }

  Future<Map<String, dynamic>> _setChatSlowMode(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final delay = QlTdEngine._int(r['slow_mode_delay']) ?? -1;
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    if (delay < 0 || delay > 86400) return _error(400, 'SLOWMODE_INVALID');
    await _apiOrThrow.patch('/conversations/${c.id}', {'slow_mode_seconds': delay});
    c.slowMode = delay;
    c.metaLoaded = true;
    return _ok;
  }

  Future<Map<String, dynamic>> _setChatPermissions(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final perms = r['permissions'];
    if (c == null || !c.isGroup || perms is! Map) return _error(400, 'Chat not found');
    final body = Map<String, dynamic>.from(perms);
    await _apiOrThrow.patch('/conversations/${c.id}', {'permissions': body});
    c.permissions = body;
    c.metaLoaded = true;
    if (c.announced) {
      _emit({
        '@type': 'updateChatPermissions',
        'chat_id': c.chatId,
        'permissions': _chatPermissions(c),
      });
    }
    return _ok;
  }

  Map<String, dynamic>? _normalizeBackground(Object? background, Object? type) {
    if (type is! Map) return null;
    Map<String, dynamic>? document;
    if (background is Map && background['@type'] == 'inputBackgroundLocal') {
      final path = _inputFilePath(background['background']);
      if (path != null && path.isNotEmpty) {
        document = {
          '@type': 'document',
          'file_name': 'wallpaper.jpg',
          'mime_type': 'image/jpeg',
          'document': {
            '@type': 'file',
            'id': 0,
            'size': 0,
            'expected_size': 0,
            'local': {
              '@type': 'localFile',
              'path': path,
              'can_be_downloaded': true,
              'can_be_deleted': false,
              'is_downloading_active': false,
              'is_downloading_completed': true,
              'download_offset': 0,
              'downloaded_prefix_size': 0,
              'downloaded_size': 0,
            },
            'remote': {
              '@type': 'remoteFile',
              'id': '',
              'unique_id': '',
              'is_uploading_active': false,
              'is_uploading_completed': true,
              'uploaded_size': 0,
            },
          },
        };
      }
    }
    return {
      '@type': 'background',
      'id': 0,
      'is_default': false,
      'is_dark': false,
      'name': '',
      'document': document,
      'type': Map<String, dynamic>.from(type),
    };
  }

  Future<Map<String, dynamic>> _setChatBackground(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || c.id.startsWith('virtual:')) return _error(400, 'Chat not found');
    final background = _normalizeBackground(r['background'], r['type']);
    if (background == null) return _error(400, 'WALLPAPER_INVALID');
    final wrapper = {
      '@type': 'chatBackground',
      'background': background,
      'dark_theme_dimming': QlTdEngine._int(r['dark_theme_dimming']) ?? 0,
    };
    await _apiOrThrow.put('/me/wallpapers', {'chat_id': c.id, 'background': wrapper});
    _wallpapers[c.id] = wrapper;
    if (c.announced) {
      _emit({
        '@type': 'updateChatBackground',
        'chat_id': c.chatId,
        'background': wrapper,
      });
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _deleteChatBackground(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || c.id.startsWith('virtual:')) return _error(400, 'Chat not found');
    await _apiOrThrow.delete('/me/wallpapers', {'chat_id': c.id});
    _wallpapers.remove(c.id);
    if (c.announced) {
      _emit({
        '@type': 'updateChatBackground',
        'chat_id': c.chatId,
        'background': null,
      });
    }
    return _ok;
  }

  Future<Map<String, dynamic>> _setDefaultBackground(Map<String, dynamic> r) async {
    final dark = r['for_dark_theme'] == true;
    final background = _normalizeBackground(r['background'], r['type']);
    if (background == null) return _error(400, 'WALLPAPER_INVALID');
    background['is_default'] = true;
    background['is_dark'] = dark;
    final key = dark ? '@default-dark' : '@default';
    await _apiOrThrow.put('/me/wallpapers', {'chat_id': key, 'background': background});
    _wallpapers[key] = background;
    _emit({
      '@type': 'updateDefaultBackground',
      'for_dark_theme': dark,
      'background': background,
    });
    return background;
  }

  Future<Map<String, dynamic>> _deleteDefaultBackground(Map<String, dynamic> r) async {
    final dark = r['for_dark_theme'] == true;
    final key = dark ? '@default-dark' : '@default';
    await _apiOrThrow.delete('/me/wallpapers', {'chat_id': key});
    _wallpapers.remove(key);
    _emit({
      '@type': 'updateDefaultBackground',
      'for_dark_theme': dark,
      'background': null,
    });
    return _ok;
  }

  String? _inviteCode(String link) {
    final text = link.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme == 'ql' && uri.host == 'join') {
      final code = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(code)) return code;
    }
    return RegExp(r'(?:ql://join/|join/)([0-9a-fA-F]{32})').firstMatch(text)?.group(1);
  }

  Map<String, dynamic> _tdInviteLink(Map<String, dynamic> raw) {
    final created = DateTime.tryParse(raw['created']?.toString() ?? '');
    return {
      '@type': 'chatInviteLink',
      'invite_link': raw['invite_link']?.toString() ?? '',
      'name': raw['name']?.toString() ?? '',
      'creator_user_id': qlUserInt(raw['creator_id']?.toString() ?? ''),
      'date': created == null ? 0 : created.millisecondsSinceEpoch ~/ 1000,
      'edit_date': 0,
      'expiration_date': QlTdEngine._int(raw['expires']) ?? 0,
      'member_limit': QlTdEngine._int(raw['member_limit']) ?? 0,
      'member_count': QlTdEngine._int(raw['uses']) ?? 0,
      'pending_join_request_count': QlTdEngine._int(raw['pending_join_request_count']) ?? 0,
      'creates_join_request': raw['creates_join_request'] == true,
      'is_primary': false,
      'is_revoked': raw['revoked'] == true,
    };
  }

  Future<Map<String, dynamic>> _createChatInviteLink(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    final raw = await _apiOrThrow.post('/conversations/${c.id}/invites', {
      'name': (r['name']?.toString() ?? '').trim(),
      'expires': QlTdEngine._int(r['expiration_date']) ?? 0,
      'member_limit': QlTdEngine._int(r['member_limit']) ?? 0,
      'creates_join_request': r['creates_join_request'] == true,
    });
    final link = _tdInviteLink(raw);
    c.inviteLink ??= link;
    return link;
  }

  Future<Map<String, dynamic>> _editChatInviteLink(Map<String, dynamic> r) async {
    final code = _inviteCode(r['invite_link']?.toString() ?? '');
    if (code == null) return _error(400, 'INVITE_HASH_INVALID');
    final raw = await _apiOrThrow.patch('/invites/$code', {
      'name': (r['name']?.toString() ?? '').trim(),
      'expires': QlTdEngine._int(r['expiration_date']) ?? 0,
      'member_limit': QlTdEngine._int(r['member_limit']) ?? 0,
      'creates_join_request': r['creates_join_request'] == true,
    });
    return _tdInviteLink(raw);
  }

  Future<Map<String, dynamic>> _revokeChatInviteLink(Map<String, dynamic> r) async {
    final code = _inviteCode(r['invite_link']?.toString() ?? '');
    if (code == null) return _error(400, 'INVITE_HASH_INVALID');
    await _apiOrThrow.delete('/invites/$code');
    return _ok;
  }

  Future<Map<String, dynamic>> _getChatInviteLinks(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    final creator = _userIdByInt[QlTdEngine._int(r['creator_user_id']) ?? 0];
    final raw = await _apiOrThrow.get('/conversations/${c.id}/invites', {
      if (r['is_revoked'] == true) 'revoked': '1',
    });
    final links = <Map<String, dynamic>>[];
    for (final item in (raw['invites'] as List? ?? const [])) {
      if (item is! Map) continue;
      final link = _tdInviteLink(Map<String, dynamic>.from(item));
      if (creator != null && item['creator_id']?.toString() != creator) continue;
      links.add(link);
    }
    return {'@type': 'chatInviteLinks', 'total_count': links.length, 'invite_links': links};
  }

  Future<Map<String, dynamic>> _getChatInviteLinkCounts(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null || !c.isGroup) return _error(400, 'Chat not found');
    final raw = await _apiOrThrow.get('/conversations/${c.id}/invites', {'revoked': 'all'});
    final active = <String, int>{};
    final revoked = <String, int>{};
    for (final item in (raw['invites'] as List? ?? const [])) {
      if (item is! Map) continue;
      final creator = item['creator_id']?.toString() ?? '';
      if (creator.isEmpty) continue;
      if (item['revoked'] == true) {
        revoked[creator] = (revoked[creator] ?? 0) + 1;
      } else {
        active[creator] = (active[creator] ?? 0) + 1;
      }
    }
    final ids = {...active.keys, ...revoked.keys};
    return {
      '@type': 'chatInviteLinkCounts',
      'invite_link_counts': [
        for (final id in ids)
          {
            '@type': 'chatInviteLinkCount',
            'user_id': qlUserInt(id),
            'invite_link_count': active[id] ?? 0,
            'revoked_invite_link_count': revoked[id] ?? 0,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _checkChatInviteLink(Map<String, dynamic> r) async {
    final code = _inviteCode(r['invite_link']?.toString() ?? '');
    if (code == null) return _error(400, 'INVITE_HASH_INVALID');
    final info = await _apiOrThrow.get('/invites/$code');
    final cid = info['chat_id']?.toString() ?? '';
    final existing = _convs[cid];
    final channel = info['kind']?.toString() == 'channel';
    return {
      '@type': 'chatInviteLinkInfo',
      'chat_id': existing != null && existing.announced ? existing.chatId : 0,
      'accessible_for': 0,
      'type': {
        '@type': channel ? 'inviteLinkChatTypeChannel' : 'inviteLinkChatTypeBasicGroup',
      },
      'title': info['title']?.toString() ?? '',
      'photo': null,
      'description': '',
      'member_count': QlTdEngine._int(info['member_count']) ?? 0,
      'member_user_ids': const <int>[],
      'creates_join_request': info['creates_join_request'] == true,
      'is_public': false,
    };
  }

  Future<Map<String, dynamic>> _joinChatByInviteLink(Map<String, dynamic> r) async {
    final code = _inviteCode(r['invite_link']?.toString() ?? '');
    if (code == null) return _error(400, 'INVITE_HASH_INVALID');
    final joined = await _apiOrThrow.post('/invites/$code/join');
    if (joined['status'] == 'requested') return _error(400, 'INVITE_REQUEST_SENT');
    final cid = joined['conversation_id']?.toString() ?? '';
    var c = _convs[cid];
    if (c == null || !c.announced) c = await _discoverConversation(cid);
    if (c == null) return _error(500, 'join_failed');
    return _tdChat(c);
  }

  Future<Map<String, dynamic>> _internalLinkType(Map<String, dynamic> r) async {
    final link = r['link']?.toString() ?? '';
    if (_inviteCode(link) != null) {
      return {'@type': 'internalLinkTypeChatInvite', 'invite_link': link};
    }
    final parsed = _classifyLink(link);
    if (parsed == null) return _unsupported('getInternalLinkType');
    return parsed;
  }

  Future<Map<String, dynamic>> _searchChatMembers(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    if (c == null) return _error(400, 'Chat not found');
    final limit = (QlTdEngine._int(r['limit']) ?? 50).clamp(1, 200);
    if (c.id.startsWith('virtual:')) {
      return {'@type': 'chatMembers', 'total_count': 0, 'members': const <Object>[]};
    }
    final query = (r['query']?.toString() ?? '').trim();
    final raw = await _apiOrThrow.get('/conversations/${c.id}/members', {
      if (query.isNotEmpty) 'q': query,
    });
    final members = <Map<String, dynamic>>[];
    for (final item in (raw['members'] as List? ?? const [])) {
      if (item is! Map) continue;
      final member = Map<String, dynamic>.from(item);
      await _ensureUser(member['user_id']?.toString() ?? '');
      members.add(_chatMember(member));
      if (members.length >= limit) break;
    }
    return {'@type': 'chatMembers', 'total_count': members.length, 'members': members};
  }

  Future<Map<String, dynamic>> _deleteChatMessagesBySender(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final sender = r['sender_id'];
    final uid = sender is Map ? _userIdByInt[QlTdEngine._int(sender['user_id']) ?? 0] : null;
    if (c == null || uid == null || c.id.startsWith('virtual:')) {
      return _error(400, 'Chat or sender not found');
    }
    await _apiOrThrow.post('/conversations/${c.id}/messages/by-sender', {'user_id': uid});
    _onMessagesDeletedBySender(c.id, {'sender_id': uid, 'through_seq': c.lastSeq});
    return _ok;
  }

  Future<Map<String, dynamic>> _addPollOption(Map<String, dynamic> r) async {
    final c = _conv(QlTdEngine._int(r['chat_id']) ?? 0);
    final mid = QlTdEngine._int(r['message_id']) ?? 0;
    if (c == null) return _error(400, 'Chat not found');
    final td = c.messages[qlSeqOf(mid)];
    final pollId = (td?['content'] is Map ? (td!['content'] as Map)['@ql_poll_id'] : null)?.toString() ?? '';
    final option = r['option'];
    var text = '';
    if (option is Map) {
      final formatted = option['text'];
      text = formatted is Map ? formatted['text']?.toString() ?? '' : formatted?.toString() ?? '';
    }
    text = text.trim();
    if (pollId.isEmpty || text.isEmpty) return _error(400, 'POLL_OPTION_INVALID');
    final raw = await _apiOrThrow.post('/conversations/${c.id}/polls/$pollId/options', {'text': text});
    final updated = _tdMessage(c, raw);
    if (updated != null) {
      _cacheMessage(c, updated, raw);
      _emit({
        '@type': 'updateMessageContent',
        'chat_id': c.chatId,
        'message_id': updated['id'],
        'new_content': updated['content'],
      });
    }
    return _ok;
  }
}
