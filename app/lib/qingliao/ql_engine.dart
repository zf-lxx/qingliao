//
//  ql_engine.dart — a pure-Dart stand-in for one TDLib client.
//
//  Receives TDLib-JSON requests (exactly what the 轻聊 UI sends to the engine) and
//  answers them from the 轻聊 backend: REST for queries and mutations, the
//  /v1/ws event stream (seq/ack, difference sync) for realtime updates. Every
//  answer and update uses TDLib's JSON shapes so the vendored UI keeps working.
//
//  Unsupported methods return a TDLib `error` object (code 400,
//  "QL_UNSUPPORTED: <method>"): never a fake success. See
//  docs/adapter-coverage.md for the coverage table.
//

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'avatar_media.dart';
import 'media_search_merge.dart';
import 'ql_api.dart';
import 'ql_ids.dart';
import 'ql_image_size.dart';
import 'ql_foreground_sync.dart';
import 'ql_proxy.dart';

part 'ql_engine_account.dart';
part 'ql_engine_convert.dart';
part 'ql_engine_files.dart';
part 'ql_engine_ops.dart';
part 'ql_engine_sync.dart';
part 'ql_engine_p2.dart';
part 'ql_engine_p3.dart';

typedef QlEmit = void Function(Map<String, dynamic> event);

/// Deep-copies JSON-like data into `Map<String, dynamic>` / `List<dynamic>`
/// so UI code can safely mutate what it receives.
Object? qlNormalizeJson(Object? value) {
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) => out[k.toString()] = qlNormalizeJson(v));
    return out;
  }
  if (value is List) return [for (final v in value) qlNormalizeJson(v)];
  return value;
}

const Map<String, dynamic> _ok = {'@type': 'ok'};

Map<String, dynamic> _error(int code, String message) => {
  '@type': 'error',
  'code': code,
  'message': message,
};

Map<String, dynamic> _unsupported(String method) =>
    _error(400, 'QL_UNSUPPORTED: $method');

/// Methods answered with an empty-but-truthful result rather than an error,
/// because the backend genuinely has nothing of that kind (no stickers
/// installed, no stories, no saved animations...). They are documented in the
/// coverage table as "empty".
const Set<String> qlEmptyResultMethods = {
  'getTrendingStickerSets',
  'getSavedAnimations',
  'getArchivedStickerSets',
  'getStoryNotificationSettingsExceptions',
  'getChatNotificationSettingsExceptions',
  'getRecentlyVisitedTMeUrls',
  'getRecentInlineBots',
  'getAttachmentMenuBot',
  'getTopChats',
  'getGroupsInCommon',
  'getSavedMessagesTopics',
  'loadSavedMessagesTopics',
  'getCustomEmojiStickers',
  'getAvailableEffects',
  'getChatSimilarChats',
  'getRecommendedChats',
  'getConnectedWebsites',
  'getChatScheduledMessages',
  'getCommunities',
};

class QlSession {
  QlSession({
    required this.server,
    required this.token,
    required this.userId,
    required this.deviceId,
    required this.handle,
    this.eventCursor = 0,
  });

  final String server;
  final String token;
  final String userId;
  final String deviceId;
  final String handle;
  int eventCursor;

  Map<String, dynamic> toJson() => {
    'server': server,
    'token': token,
    'user_id': userId,
    'device_id': deviceId,
    'handle': handle,
    'event_cursor': eventCursor,
  };

  static QlSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final server = raw['server'];
    final token = raw['token'];
    final userId = raw['user_id'];
    if (server is! String || token is! String || userId is! String) {
      return null;
    }
    return QlSession(
      server: server,
      token: token,
      userId: userId,
      deviceId: raw['device_id']?.toString() ?? '',
      handle: raw['handle']?.toString() ?? '',
      eventCursor: (raw['event_cursor'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One conversation as the engine tracks it.
class _Conv {
  _Conv(this.id);

  final String id;
  String kind = 'direct';
  String title = '';
  int lastSeq = 0;
  int lastActivityMicros = 0;
  int readSeq = 0;
  String role = 'member';
  bool archived = false;
  int pinnedOrder = 0;
  int muteUntil = 0;
  bool manualUnread = false;
  int unread = 0;
  int mentions = 0;
  String? peerId;
  int peerReadSeq = 0;
  bool readReceiptsVisible = true;
  int? lastMessageReadCount;
  Map<String, dynamic>? lastMessage; // TDLib message
  int chatId = 0;
  bool announced = false;
  List<Map<String, dynamic>> members = const [];
  bool membersLoaded = false;
  String avatarMediaId = '';
  final Set<int> pinnedSeqs = {};
  final Map<int, List<Map<String, String>>> reactionsBySeq = {};
  final SplayTreeMap<int, Map<String, dynamic>> messages = SplayTreeMap();
  final Map<String, Map<String, dynamic>> draft = {};

  bool get isGroup => kind != 'direct';
  bool get isChannel => kind == 'channel';
  bool get isBasicGroup => kind == 'group';
}

class _Pending {
  _Pending({
    required this.conv,
    required this.tempId,
    required this.clientMsgId,
    required this.message,
  });

  _Conv conv;
  final int tempId;
  final String clientMsgId;
  Map<String, dynamic> message;
  bool done = false;
}

class QlTdEngine {
  QlTdEngine({required this.clientId, required QlEmit emit}) : _emit = emit;

  final int clientId;
  final QlEmit _emit;

  static final math.Random _random = math.Random.secure();

  // ---- lifecycle
  bool _activated = false;
  bool _closed = false;
  String _authState = 'authorizationStateWaitTdlibParameters';
  String _databaseDir = '';
  String _filesDir = '';
  QlSession? _session;
  QlApi? _api;
  Future<void>? _initialLoad;
  List<QlProxyConfig> _proxies = [];
  int _proxySeq = 0;
  final Map<int, String> _deviceByInt = {};
  final Map<int, String> _albumByInt = {};

  // ---- state
  final Set<String> _blockedUserIds = {};
  final Map<String, Map<String, dynamic>> _users = {}; // backend id -> raw
  final Map<int, String> _userIdByInt = {};
  final Map<String, _Conv> _convs = {};
  final Map<int, _Conv> _convByChatId = {};
  final Map<String, (String, int)> _messageRef = {}; // msg id -> (conv, seq)
  final Map<String, _Pending> _pendingByClientId = {};
  final Map<int, _Pending> _pendingByTempId = {};
  int _pendingCounter = 0;
  final Set<int> _openChats = {};
  final Map<String, Timer> _typingTimers = {};
  Timer? _persistTimer;
  final Map<String, List<int>> _mediaDims = {};
  final Map<int, _QlFile> _files = {};
  final Map<String, Map<String, dynamic>> _folders = {};
  final Map<int, String> _folderIdByInt = {};
  final Set<String> _contactIds = {};
  final Map<String, Map<String, dynamic>> _scopeNotifs = {};
  bool _activeStoriesLoaded = false;
  int _mainChatListPosition = 0;

  // ---- realtime socket
  WebSocket? _socket;
  int _socketGeneration = 0;
  Timer? _reconnectTimer;
  Timer? _socketPing;
  Timer? _ackTimer;
  int _backoffSeconds = 1;
  bool _connecting = false;
  String _connectionState = 'connectionStateConnecting';
  int _ackedCursor = 0;
  final Map<String, Set<String>> _servedLists = {};
  Future<void> _eventChain = Future<void>.value();

  String get _myId => _session?.userId ?? '';
  int get _myInt => qlUserInt(_myId);

  // MARK: - Entry points

  static Map<String, dynamic> executeSync(Map<String, dynamic> request) {
    switch (request['@type']) {
      case 'setLogVerbosityLevel':
      case 'setLogStream':
        return _ok;
      case 'getTextEntities':
        return {
          '@type': 'textEntities',
          'entities': _detectEntities(request['text']?.toString() ?? ''),
        };
      case 'parseMarkdown':
        final text = request['text'];
        return text is Map<String, dynamic> ? text : _formatted('');
      case 'getMarkdownText':
        final text = request['text'];
        return text is Map<String, dynamic> ? text : _formatted('');
      default:
        return _unsupported(request['@type']?.toString() ?? '');
    }
  }

  void resume() {
    if (_closed || _session == null) return;
    _ensureSocket(immediate: true);
  }

  Future<Map<String, dynamic>> handle(Map<String, dynamic> request) async {
    if (_closed && request['@type'] != 'close') {
      return _error(500, 'Client is closed');
    }
    final type = request['@type']?.toString() ?? '';
    try {
      return await _dispatch(type, request);
    } on QlApiException catch (e) {
      return _error(_tdCode(e.statusCode), _humanError(e));
    } on FormatException catch (e) {
      return _error(400, e.message);
    } on TimeoutException {
      return _error(504, 'NETWORK_TIMEOUT');
    } on SocketException {
      return _error(503, 'NETWORK_UNAVAILABLE');
    } on HttpException {
      return _error(503, 'NETWORK_UNAVAILABLE');
    } catch (e) {
      return _error(500, 'QL_INTERNAL: $type: $e');
    }
  }

  int _tdCode(int http) => switch (http) {
    401 => 401,
    403 => 403,
    404 => 404,
    409 => 400,
    413 => 400,
    429 => 429,
    _ => http >= 500 ? 500 : 400,
  };

  String _humanError(QlApiException e) => switch (e.error) {
    'unauthorized' || 'invalid_credentials' => '账号或密码错误',
    'invalid_totp' => '两步验证码不正确',
    'invalid_invite' => '邀请码无效或已用完',
    'handle_taken' => '这个用户名已被占用',
    'forbidden' => '没有权限',
    'conflict' => '已经开启两步验证',
    _ => e.error,
  };

  // MARK: - Dispatch

  Future<Map<String, dynamic>> _dispatch(
    String type,
    Map<String, dynamic> r,
  ) async {
    if (!_activated) {
      _activated = true;
      _emitAuth();
    }
    switch (type) {
      // --- auth / lifecycle
      case 'getOption':
        return _option(r['name']?.toString() ?? '');
      case 'setOption':
        return _ok;
      case 'setTdlibParameters':
        return _setParameters(r);
      case 'getAuthorizationState':
        return {'@type': _authState};
      case 'qlLogin':
        return _login(r, register: false);
      case 'qlRegister':
        return _login(r, register: true);
      case 'qlLoginTotp':
        return _loginTotp(r);
      case 'getPasswordState':
        return _getPasswordState();
      case 'setPassword':
        return _setPassword(r);
      case 'qlStartTotp':
        return _startTotp();
      case 'qlConfirmTotp':
        return _confirmTotp(r);
      case 'qlDisableTotp':
        return _disableTotp(r);
      case 'deleteAccount':
        return _deleteAccount(r);
      case 'getActiveSessions':
        return _getActiveSessions();
      case 'terminateSession':
        return _terminateSession(r);
      case 'terminateAllOtherSessions':
        return _terminateOtherSessions();
      case 'createNewStickerSet':
        return _createNewStickerSet(r);
      case 'addStickerToSet':
        return _addStickerToSet(r);
      case 'deleteStickerSet':
        return _deleteStickerSet(r);
      case 'setStickerSetTitle':
        return _setStickerSetTitle(r);
      case 'removeStickerFromSet':
        return _removeStickerFromSet(r);
      case 'setStickerPositionInSet':
        return _setStickerPositionInSet(r);
      case 'setStickerSetThumbnail':
        return _setStickerSetThumbnail(r);
      case 'changeStickerSet':
        return _changeStickerSet(r);
      case 'createStoryAlbum':
        return _createStoryAlbum(r);
      case 'getStoryAlbumStories':
        return _getStoryAlbumStories(r);
      case 'setStoryAlbumName':
        return _setStoryAlbumName(r);
      case 'reorderStoryAlbums':
        return _reorderStoryAlbums(r);
      case 'deleteStoryAlbum':
        return _deleteStoryAlbum(r);
      case 'addStoryAlbumStories':
        return _mutateStoryAlbumStories(r, 'add');
      case 'removeStoryAlbumStories':
        return _mutateStoryAlbumStories(r, 'remove');
      case 'reorderStoryAlbumStories':
        return _mutateStoryAlbumStories(r, 'reorder');
      case 'qlListBots':
        return _listBots();
      case 'qlCreateBot':
        return _createBot(r);
      case 'qlRevokeBotToken':
        return _revokeBotToken(r);
      case 'qlDeleteBot':
        return _deleteBot(r);
      case 'qlGetServer':
        return {
          '@type': 'qlServer',
          'server': _session?.server ?? qlDefaultServer,
        };
      case 'logOut':
        return _logOut();
      case 'close':
        return _close();
      case 'destroy':
        return _close();
      case 'getMe':
        return _requireMe();
      case 'getConnectionState':
        return {'@type': _connectionState};
      case 'getCurrentState':
        return {'@type': 'updates', 'updates': _currentStateUpdates()};
      case 'setNetworkType':
      case 'setAlarm':
      case 'testNetwork':
      case 'registerDevice':
        return _ok;
      case 'addProxy':
        return _addProxy(r);
      case 'editProxy':
        return _editProxy(r);
      case 'removeProxy':
        return _removeProxy(r);
      case 'enableProxy':
        return _enableProxy(r, enabled: true);
      case 'disableProxy':
      case 'setProxy':
        return _enableProxy(r, enabled: false);
      case 'getProxies':
        return _getProxies();
      case 'pingProxy':
        return _pingProxy(r);
      // --- chats
      case 'loadChats':
        return _loadChats(r);
      case 'getChats':
        if (!_hasServableLocalChats) await _waitInitialLoad();
        final list = _sortedConvs(r['chat_list']);
        final limit = _int(r['limit']) ?? 100;
        return {
          '@type': 'chats',
          'total_count': list.length,
          'chat_ids': [for (final c in list.take(limit)) c.chatId],
        };
      case 'getChat':
        return _getChat(_int(r['chat_id']) ?? 0);
      case 'openChat':
        _openChats.add(_int(r['chat_id']) ?? 0);
        return _ok;
      case 'closeChat':
        _openChats.remove(_int(r['chat_id']) ?? 0);
        return _ok;
      case 'createPrivateChat':
        return _createPrivateChat(_int(r['user_id']) ?? 0);
      case 'createNewBasicGroupChat':
        return _createGroup(r);
      case 'searchChats':
      case 'searchChatsOnServer':
        return _searchChats(r);
      case 'searchPublicChats':
      case 'searchContacts':
        return _searchUsers(r, chats: type == 'searchPublicChats');
      case 'searchPublicChat':
        return _searchPublicChat(r['username']?.toString() ?? '');
      case 'getContacts':
        return _getContactsTd();
      case 'toggleChatIsPinned':
        return _togglePinned(r);
      case 'toggleChatIsMarkedAsUnread':
        return _markUnread(r);
      case 'setChatNotificationSettings':
        return _setChatNotifications(r);
      case 'addChatToList':
        return _addChatToList(r);
      case 'setChatDraftMessage':
        return _setDraft(r);
      case 'setChatTitle':
        return _doSetChatTitle(r);
      case 'setChatPhoto':
      case 'deleteChatPhoto':
        return _setChatPhoto(type == 'deleteChatPhoto' ? {...r, 'photo': null} : r);
      case 'createNewSupergroupChat':
        return _createSupergroup(r);
      case 'getSupergroup':
        return _supergroupById(_int(r['supergroup_id']) ?? 0);
      case 'getSupergroupFullInfo':
        return _supergroupFullInfo(_int(r['supergroup_id']) ?? 0);
      case 'leaveChat':
        return _leaveChat(r);
      case 'getChatMember':
        return _getChatMember(r);
      case 'getBasicGroup':
        return _basicGroupById(_int(r['basic_group_id']) ?? 0);
      case 'getBasicGroupFullInfo':
        return _basicGroupFullInfo(_int(r['basic_group_id']) ?? 0);
      case 'getChatAdministrators':
        return _chatAdministrators(_int(r['chat_id']) ?? 0);
      case 'addChatMember':
        return _addChatMember(r);
      case 'addChatMembers':
        return _addChatMembers(r);
      case 'setChatMemberStatus':
        return _setChatMemberStatus(r);
      case 'getScopeNotificationSettings':
        return _getScopeNotifications(r);
      case 'getChatListsToAddChat':
        return {'@type': 'chatLists', 'chat_lists': const [{'@type': 'chatListMain'}, {'@type': 'chatListArchive'}]};
      // --- messages
      case 'getChatHistory':
        return _history(r);
      case 'getMessage':
      case 'getMessageLocally':
        return _getMessage(_int(r['chat_id']) ?? 0, _int(r['message_id']) ?? 0,
            localOnly: type == 'getMessageLocally');
      case 'getMessages':
        return _getMessages(r);
      case 'getRepliedMessage':
        return _getRepliedMessage(r);
      case 'viewMessages':
        return _viewMessages(r);
      case 'readAllChatMentions':
      case 'readAllChatReactions':
        return _ok;
      case 'sendMessage':
        return _sendMessage(r);
      case 'sendMessageAlbum':
        return _sendAlbum(r);
      case 'resendMessages':
        return _resend(r);
      case 'editMessageText':
        return _editText(r, caption: false);
      case 'editMessageCaption':
        return _editText(r, caption: true);
      case 'deleteMessages':
        return _deleteMessages(r);
      case 'sendChatAction':
        return _sendChatAction(r);
      case 'searchChatMessages':
        return _searchChatMessages(r);
      case 'searchMessages':
        return _searchMessages(r);
      case 'getChatMessageCount':
        return _messageCount(r);
      case 'forwardMessages':
        return _forwardMessages(r);
      case 'pinChatMessage':
        return _pinMessage(r, remove: false);
      case 'unpinChatMessage':
        return _pinMessage(r, remove: true);
      case 'unpinAllChatMessages':
        return _unpinAll(r);
      case 'addMessageReaction':
        return _setReaction(r, remove: false);
      case 'removeMessageReaction':
        return _setReaction(r, remove: true);
      case 'getMessageAvailableReactions':
        return _availableReactions();
      case 'getMessageAddedReactions':
        return _addedReactions(r);
      case 'setMessageSenderBlockList':
        return _setSenderBlockList(r);
      case 'getBlockedMessageSenders':
        return _blockedSenders(r);
      case 'deleteChatHistory':
        return _deleteChatHistory(r);
      case 'reportChat':
        return _reportChat(r);
      case 'getMessageProperties':
        return _messageProperties(r);
      case 'getMessageLink':
        return _unsupported(type);
      // --- users
      case 'getUser':
        return _getUser(_int(r['user_id']) ?? 0);
      case 'getUserFullInfo':
        return _userFullInfo(_int(r['user_id']) ?? 0);
      case 'getUserProfilePhotos':
        return _userProfilePhotos(_int(r['user_id']) ?? 0);
      case 'setName':
        return _setName(r);
      case 'setProfilePhoto':
        return _setProfilePhoto(r);
      case 'deleteProfilePhoto':
        return _deleteProfilePhoto();
      // --- files
      case 'getFile':
        return _getFile(_int(r['file_id']) ?? 0);
      case 'downloadFile':
        return _downloadFile(r);
      case 'cancelDownloadFile':
        return _ok;
      case 'addFileToDownloads':
        return _downloadFile({...r, 'synchronous': false});
      case 'getRemoteFile':
        return _getRemoteFile(r['remote_file_id']?.toString() ?? '');
      case 'deleteFile':
        return _deleteLocalFile(_int(r['file_id']) ?? 0);
      case 'readFilePart':
        return _readFilePart(r);
      // --- misc pure helpers
      case 'getTextEntities':
      case 'parseMarkdown':
      case 'getMarkdownText':
      case 'setLogVerbosityLevel':
        return executeSync(r);
      case 'parseTextEntities':
        return _formatted(r['text']?.toString() ?? '');
      default:
        final p3 = await _dispatchP3(type, r);
        if (p3 != null) return p3;
        if (qlEmptyResultMethods.contains(type)) return _emptyResult(type);
        return _unsupported(type);
    }
  }

  Map<String, dynamic> _emptyResult(String type) {
    switch (type) {
      case 'getInstalledStickerSets':
      case 'getTrendingStickerSets':
      case 'getArchivedStickerSets':
        return {'@type': 'stickerSets', 'total_count': 0, 'sets': const <Object>[]};
      case 'getRecentStickers':
      case 'getFavoriteStickers':
      case 'getStickers':
      case 'searchStickers':
      case 'getCustomEmojiStickers':
        return {'@type': 'stickers', 'stickers': const <Object>[]};
      case 'getSavedAnimations':
        return {'@type': 'animations', 'animations': const <Object>[]};
      case 'getConnectedWebsites':
        return {'@type': 'connectedWebsites', 'websites': const <Object>[]};
      case 'getAvailableEffects':
        return {'@type': 'availableEffects', 'effects': const <Object>[]};
      case 'getRecentlyVisitedTMeUrls':
        return {'@type': 'tMeUrls', 'urls': const <Object>[]};
      case 'getBlockedMessageSenders':
        return {'@type': 'messageSenders', 'total_count': 0, 'senders': const <Object>[]};
      case 'getChatScheduledMessages':
        return {'@type': 'messages', 'total_count': 0, 'messages': const <Object>[]};
      case 'getRecentInlineBots':
      case 'getTopChats':
        return {'@type': 'users', 'total_count': 0, 'user_ids': const <int>[]};
      case 'loadActiveStories':
      case 'loadSavedMessagesTopics':
        return _error(404, 'Not Found');
      case 'getAttachmentMenuBot':
        return _unsupported(type);
      default:
        return {'@type': 'chats', 'total_count': 0, 'chat_ids': const <int>[]};
    }
  }

  // MARK: - Auth

  void _emitAuth() {
    _emit({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': _authState},
    });
  }

  void _setAuth(String state) {
    if (_authState == state) return;
    _authState = state;
    _emitAuth();
  }

  Map<String, dynamic> _option(String name) {
    switch (name) {
      case 'version':
        return {'@type': 'optionValueString', 'value': 'qingliao-1'};
      case 'my_id':
        return _session == null
            ? {'@type': 'optionValueEmpty'}
            : {'@type': 'optionValueInteger', 'value': _myInt};
      case 'can_use_login_passkey':
      case 'is_premium_available':
      case 'can_use_text_entities_in_story_caption':
        return {'@type': 'optionValueBoolean', 'value': false};
      case 'message_text_length_max':
        return {'@type': 'optionValueInteger', 'value': 16000};
      case 'message_caption_length_max':
        return {'@type': 'optionValueInteger', 'value': 4000};
      case 'poll_answer_count_max':
        return {'@type': 'optionValueInteger', 'value': 10};
      case 'poll_question_length_max':
        return {'@type': 'optionValueInteger', 'value': 1000};
      case 'poll_option_length_max':
        return {'@type': 'optionValueInteger', 'value': 300};
      case 'checklist_task_count_max':
        return {'@type': 'optionValueInteger', 'value': 30};
      default:
        return {'@type': 'optionValueEmpty'};
    }
  }

  String get _sessionPath => '$_databaseDir/qingliao_session.json';
  String get _statePath => '$_databaseDir/qingliao_state.json';
  String get _proxyPath => '$_databaseDir/qingliao_proxies.json';

  Future<Map<String, dynamic>> _setParameters(Map<String, dynamic> r) async {
    if (_databaseDir.isNotEmpty) return _ok; // idempotent (hot restart)
    _databaseDir = r['database_directory']?.toString() ?? '';
    _filesDir = r['files_directory']?.toString() ?? '$_databaseDir/files';
    if (_databaseDir.isEmpty) return _error(400, 'database_directory required');
    await Directory(_databaseDir).create(recursive: true);
    _loadProxies();
    _loadState();
    QlSession? session;
    try {
      final file = File(_sessionPath);
      if (file.existsSync()) {
        session = QlSession.fromJson(jsonDecode(file.readAsStringSync()));
      }
    } on FormatException {
      session = null;
    } on FileSystemException {
      session = null;
    }
    if (session == null) {
      _setAuth('authorizationStateWaitPhoneNumber');
      return _ok;
    }
    _startSession(session);
    return _ok;
  }

  Future<Map<String, dynamic>> _login(
    Map<String, dynamic> r, {
    required bool register,
  }) async {
    if (_databaseDir.isEmpty) return _error(400, 'Client is not initialized');
    final server = qlNormalizeServer(r['server']?.toString() ?? '');
    final handle = (r['handle']?.toString() ?? '').trim().toLowerCase();
    final password = r['password']?.toString() ?? '';
    if (handle.isEmpty || password.isEmpty) {
      return _error(400, '请填写用户名和密码');
    }
    final api = QlApi(server, proxy: _activeProxy);
    try {
      final body = <String, dynamic>{
        'handle': handle,
        'password': password,
        'platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
        'app_name': '轻聊',
        'app_version': '0.4.2',
        'device_model': Platform.operatingSystem,
        if ((r['totp_code']?.toString() ?? '').isNotEmpty)
          'totp_code': r['totp_code'].toString(),
        if ((r['recovery_code']?.toString() ?? '').isNotEmpty)
          'recovery_code': r['recovery_code'].toString(),
      };
      if (register) {
        body['invite_code'] = (r['invite_code']?.toString() ?? '').trim();
        final name = (r['display_name']?.toString() ?? '').trim();
        if (name.isNotEmpty) body['display_name'] = name;
      }
      final result = await api.post(
        register ? '/auth/register' : '/auth/login',
        body,
      );
      if (result['two_factor_required'] == true) {
        return {
          '@type': 'qlTwoFactorRequired',
          'pending_token': result['pending_token']?.toString() ?? '',
        };
      }
      final token = result['access_token']?.toString() ?? '';
      final userId = result['user_id']?.toString() ?? '';
      if (token.isEmpty || userId.isEmpty) {
        return _error(500, '服务器返回异常');
      }
      final session = QlSession(
        server: server.toString(),
        token: token,
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

  void _writeSession(QlSession session) {
    final file = File(_sessionPath);
    file.writeAsStringSync(jsonEncode(session.toJson()), flush: true);
    // The multi-account quarantine deletes slots that lack td.binlog.
    final marker = File('$_databaseDir/td.binlog');
    if (!marker.existsSync()) {
      marker.writeAsBytesSync(utf8.encode('QLSESS01'), flush: true);
    }
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  void _startSession(QlSession session) {
    _session = session;
    _api?.close();
    _api = QlApi(Uri.parse(session.server), token: session.token, proxy: _activeProxy);
    _emit({
      '@type': 'updateOption',
      'name': 'my_id',
      'value': {'@type': 'optionValueInteger', 'value': _myInt},
    });
    // Seed a minimal self user so the UI never sees an unknown "me".
    _users.putIfAbsent(
      session.userId,
      () => {
        'id': session.userId,
        'handle': session.handle,
        'display_name': session.handle,
        'avatar_media_id': '',
        'online': true,
        'last_seen': '',
      },
    );
    _userIdByInt[_myInt] = session.userId;
    _emit({'@type': 'updateUser', 'user': _tdUser(session.userId)});
    _setAuth('authorizationStateReady');
    _announceRestoredChats();
    _initialLoad = _runInitialLoad();
    unawaited(QlForegroundSync.start());
  }

  Future<Map<String, dynamic>> _logOut() async {
    final api = _api;
    _setAuth('authorizationStateLoggingOut');
    if (api != null) {
      try {
        await api.post('/auth/logout');
      } catch (_) {}
    }
    await QlForegroundSync.stop();
    _teardown();
    try {
      File(_sessionPath).deleteSync();
    } catch (_) {}
    try {
      File(_statePath).deleteSync();
    } catch (_) {}
    _setAuth('authorizationStateClosing');
    _setAuth('authorizationStateClosed');
    _closed = true;
    return _ok;
  }

  Future<Map<String, dynamic>> _close() async {
    if (_closed) return _ok;
    _flushState();
    _teardown();
    _setAuth('authorizationStateClosing');
    _setAuth('authorizationStateClosed');
    _closed = true;
    return _ok;
  }

  void _teardown() {
    _socketGeneration++;
    _reconnectTimer?.cancel();
    _socketPing?.cancel();
    unawaited(_socket?.close());
    _socket = null;
    _api?.close();
    _api = null;
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
  }

  Map<String, dynamic> _requireMe() {
    if (_session == null) return _error(401, 'Unauthorized');
    return _tdUser(_myId);
  }

  List<Map<String, dynamic>> _currentStateUpdates() => [
    {
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': _authState},
    },
    if (_session != null) {'@type': 'updateUser', 'user': _tdUser(_myId)},
    for (final id in _users.keys)
      if (id != _myId) {'@type': 'updateUser', 'user': _tdUser(id)},
    for (final c in _convs.values)
      if (c.announced) {'@type': 'updateNewChat', 'chat': _tdChat(c)},
    if (_folders.isNotEmpty) _chatFoldersUpdate(),
  ];

  // MARK: - Local state persistence (id maps, cursor, media sizes)

  bool get _hasServableLocalChats =>
      _convs.values.any((c) => c.chatId != 0);

  static const _persistedChatCap = 200;
  static const _persistedMessageCap = 80;

  void _loadState() {
    try {
      final file = File(_statePath);
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return;
      final dims = raw['media_dims'];
      if (dims is Map) {
        dims.forEach((k, v) {
          if (v is List && v.length == 2) {
            _mediaDims[k.toString()] = [
              (v[0] as num).toInt(),
              (v[1] as num).toInt(),
            ];
          }
        });
      }
      final users = raw['users'];
      if (users is Map) {
        users.forEach((k, v) {
          if (v is Map) {
            final id = k.toString();
            _users[id] = Map<String, dynamic>.from(v);
            _userIdByInt[qlUserInt(id)] = id;
          }
        });
      }
      final conversations = raw['conversations'];
      if (conversations is List) {
        for (final item in conversations) {
          if (item is Map) _restoreConvSnapshot(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {}
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), _flushState);
  }

  void _flushState() {
    _persistTimer?.cancel();
    if (_databaseDir.isEmpty || _closed) return;
    try {
      File(_statePath).writeAsStringSync(
        jsonEncode({
          'media_dims': _mediaDims,
          'users': _users,
          'conversations': _conversationSnapshots(),
        }),
      );
      final session = _session;
      if (session != null) _writeSession(session);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _conversationSnapshots() {
    final convs = _convs.values.toList()
      ..sort((a, b) => b.lastActivityMicros.compareTo(a.lastActivityMicros));
    final limited = convs.take(_persistedChatCap).toList();
    return [
      for (var i = 0; i < limited.length; i++)
        _convSnapshot(limited[i], includeMessages: i < 24),
    ];
  }

  Map<String, dynamic> _convSnapshot(_Conv c, {required bool includeMessages}) {
    final messages = <Map<String, dynamic>>[];
    if (includeMessages && c.messages.isNotEmpty) {
      final values = c.messages.values.toList();
      final start = math.max(0, values.length - _persistedMessageCap);
      for (final message in values.sublist(start)) {
        try {
          messages.add(Map<String, dynamic>.from(jsonDecode(jsonEncode(message))));
        } catch (_) {}
      }
    }
    return {
      'id': c.id,
      'kind': c.kind,
      'title': c.title,
      'lastSeq': c.lastSeq,
      'lastActivityMicros': c.lastActivityMicros,
      'readSeq': c.readSeq,
      'role': c.role,
      'archived': c.archived,
      'pinnedOrder': c.pinnedOrder,
      'muteUntil': c.muteUntil,
      'manualUnread': c.manualUnread,
      'unread': c.unread,
      'mentions': c.mentions,
      'peerId': c.peerId,
      'peerReadSeq': c.peerReadSeq,
      'readReceiptsVisible': c.readReceiptsVisible,
      'lastMessageReadCount': c.lastMessageReadCount,
      'chatId': c.chatId,
      'membersLoaded': c.membersLoaded,
      'avatarMediaId': c.avatarMediaId,
      if (c.lastMessage != null) 'lastMessage': _jsonSafeMap(c.lastMessage),
      if (c.members.isNotEmpty) 'members': c.members,
      if (messages.isNotEmpty) 'messages': messages,
    };
  }

  void _restoreConvSnapshot(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final c = _convs.putIfAbsent(id, () => _Conv(id));
    c.kind = raw['kind']?.toString() ?? c.kind;
    c.title = raw['title']?.toString() ?? c.title;
    c.lastSeq = QlTdEngine._int(raw['lastSeq']) ?? c.lastSeq;
    c.lastActivityMicros =
        QlTdEngine._int(raw['lastActivityMicros']) ?? c.lastActivityMicros;
    c.readSeq = QlTdEngine._int(raw['readSeq']) ?? c.readSeq;
    c.role = raw['role']?.toString() ?? c.role;
    c.archived = raw['archived'] == true;
    c.pinnedOrder = QlTdEngine._int(raw['pinnedOrder']) ?? c.pinnedOrder;
    c.muteUntil = QlTdEngine._int(raw['muteUntil']) ?? c.muteUntil;
    c.manualUnread = raw['manualUnread'] == true;
    c.unread = QlTdEngine._int(raw['unread']) ?? c.unread;
    c.mentions = QlTdEngine._int(raw['mentions']) ?? c.mentions;
    c.peerId = raw['peerId']?.toString() ?? c.peerId;
    c.peerReadSeq = QlTdEngine._int(raw['peerReadSeq']) ?? c.peerReadSeq;
    c.readReceiptsVisible = raw['readReceiptsVisible'] != false;
    c.lastMessageReadCount = QlTdEngine._int(raw['lastMessageReadCount']);
    c.membersLoaded = raw['membersLoaded'] == true;
    c.avatarMediaId = raw['avatarMediaId']?.toString() ?? c.avatarMediaId;
    final lastMessage = raw['lastMessage'];
    if (lastMessage is Map) {
      c.lastMessage = Map<String, dynamic>.from(lastMessage);
    }
    final members = raw['members'];
    if (members is List) {
      c.members = [
        for (final member in members)
          if (member is Map) Map<String, dynamic>.from(member),
      ];
    }
    final chatId = QlTdEngine._int(raw['chatId']) ?? 0;
    if (chatId != 0) {
      c.chatId = chatId;
      _convByChatId[chatId] = c;
    } else {
      _assignChatId(c);
    }
    c.announced = false;
    final messages = raw['messages'];
    if (messages is List) {
      for (final item in messages) {
        if (item is! Map) continue;
        final td = Map<String, dynamic>.from(item);
        final messageId = QlTdEngine._int(td['id']) ?? 0;
        if (messageId == 0) continue;
        final seq = qlSeqOf(messageId);
        c.messages[seq] = td;
        final backendId = td['@ql_id']?.toString() ?? '';
        if (backendId.isNotEmpty) _messageRef[backendId] = (c.id, seq);
      }
    }
  }

  void _announceRestoredChats() {
    for (final c in _convs.values) {
      c.announced = false;
      _announce(c);
    }
  }

  Map<String, dynamic>? _jsonSafeMap(Map<String, dynamic>? value) {
    if (value == null) return null;
    try {
      final encoded = jsonDecode(jsonEncode(value));
      if (encoded is Map) return Map<String, dynamic>.from(encoded);
    } catch (_) {}
    return null;
  }

  void _publishAnnouncedChat(_Conv c) {
    if (c.chatId == 0) _assignChatId(c);
    if (c.chatId == 0) return;
    if (c.lastMessage != null && c.lastMessage!['chat_id'] != c.chatId) {
      c.lastMessage!['chat_id'] = c.chatId;
    }
    _emit({
      '@type': 'updateChatTitle',
      'chat_id': c.chatId,
      'title': c.isGroup
          ? c.title
          : (_users[c.peerId ?? '']?['display_name'] ?? c.title),
    });
    _emit({
      '@type': 'updateChatLastMessage',
      'chat_id': c.chatId,
      'last_message': c.lastMessage,
      'positions': [_position(c)],
    });
    _emit({
      '@type': 'updateChatReadInbox',
      'chat_id': c.chatId,
      'last_read_inbox_message_id': _lastReadInboxId(c),
      'unread_count': c.unread,
    });
    _emit({
      '@type': 'updateChatReadOutbox',
      'chat_id': c.chatId,
      'last_read_outbox_message_id': _lastReadOutboxId(c),
    });
    _emit({
      '@type': 'updateChatNotificationSettings',
      'chat_id': c.chatId,
      'notification_settings': _notificationSettings(c),
    });
    _emit({
      '@type': 'updateChatIsMarkedAsUnread',
      'chat_id': c.chatId,
      'is_marked_as_unread': c.manualUnread,
    });
  }

  // MARK: - Helpers

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  String _newClientMsgId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  QlApi get _apiOrThrow {
    final api = _api;
    if (api == null) throw const QlApiException(401, 'unauthorized');
    return api;
  }

  Future<void> _waitInitialLoad() async {
    final load = _initialLoad;
    if (load == null) return;
    try {
      await load.timeout(const Duration(seconds: 20));
    } catch (_) {}
  }
}
