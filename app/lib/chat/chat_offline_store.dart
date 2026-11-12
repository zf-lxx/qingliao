import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../tdlib/td_models.dart';
import 'chat_offline_codec.dart';
import 'chat_session_cache.dart';

/// On-disk snapshots of the chat list and recently opened transcripts.
///
/// Reads are synchronous after [preload], so the first frame of the chat list
/// or a reopened conversation can paint last session's content without waiting
/// on the network. Writes are coalesced so they never stall launch or scroll.
class ChatOfflineStore {
  ChatOfflineStore._();

  static final ChatOfflineStore instance = ChatOfflineStore._();

  static const _writeDelay = Duration(seconds: 2);
  static const _transcriptMessageCap = 80;

  bool get isReady => _directory != null;

  Directory? _directory;
  final Map<int, List<ChatSummary>> _lists = {};
  final Map<String, _StoredTranscript> _transcripts = {};
  Timer? _listWriteTimer;
  Timer? _transcriptWriteTimer;
  bool _listDirty = false;
  bool _transcriptDirty = false;

  /// Last persisted list for [accountSlot], already in memory after preload.
  List<ChatSummary> listSnapshot(int accountSlot) =>
      List<ChatSummary>.from(_lists[accountSlot] ?? const []);

  ChatSessionRenderState? transcriptSnapshot({
    required int accountSlot,
    required int chatId,
    int? forumTopicId,
  }) => _transcripts[_key(accountSlot, chatId, forumTopicId)]?.state;

  ChatSessionScrollSnapshot? scrollSnapshot({
    required int accountSlot,
    required int chatId,
    int? forumTopicId,
  }) => _transcripts[_key(accountSlot, chatId, forumTopicId)]?.scroll;

  Future<void> preload({Directory? directory}) async {
    _directory = directory ?? await getApplicationSupportDirectory();
    _loadListsFromDisk();
    _loadTranscriptsFromDisk();
  }

  void preloadSync(Directory directory) {
    _directory = directory;
    _loadListsFromDisk();
    _loadTranscriptsFromDisk();
  }

  void resetForTesting() {
    _listWriteTimer?.cancel();
    _transcriptWriteTimer?.cancel();
    _listWriteTimer = null;
    _transcriptWriteTimer = null;
    _directory = null;
    _lists.clear();
    _transcripts.clear();
    _listDirty = false;
    _transcriptDirty = false;
  }

  void rememberList(int accountSlot, List<ChatSummary> chats) {
    _lists[accountSlot] = [for (final chat in chats) chat];
    if (_directory == null) return;
    _listDirty = true;
    _listWriteTimer?.cancel();
    _listWriteTimer = Timer(_writeDelay, flushLists);
  }

  void rememberTranscript({
    required int accountSlot,
    required int chatId,
    int? forumTopicId,
    required ChatSessionRenderState state,
    ChatSessionScrollSnapshot? scroll,
  }) {
    final messages = state.messages.length > _transcriptMessageCap
        ? state.messages.sublist(state.messages.length - _transcriptMessageCap)
        : state.messages;
    _transcripts[_key(accountSlot, chatId, forumTopicId)] = _StoredTranscript(
      state: ChatSessionRenderState(
        messages: List<ChatMessage>.unmodifiable(messages),
        anchoredHistory: state.anchoredHistory,
        olderHistoryExhausted: state.olderHistoryExhausted,
        firstContactInfo: state.firstContactInfo,
      ),
      scroll: scroll,
    );
    if (_directory == null) return;
    _transcriptDirty = true;
    _transcriptWriteTimer?.cancel();
    _transcriptWriteTimer = Timer(_writeDelay, flushTranscripts);
  }

  void hydrateSessionCache(ChatSessionCache cache) {
    for (final entry in _transcripts.entries) {
      final parsed = _parseKey(entry.key);
      if (parsed == null) continue;
      final state = entry.value.state;
      if (state.messages.isEmpty) continue;
      cache.store(
        accountSlot: parsed.accountSlot,
        chatId: parsed.chatId,
        forumTopicId: parsed.forumTopicId,
        messages: state.messages,
        anchoredHistory: state.anchoredHistory,
        olderHistoryExhausted: state.olderHistoryExhausted,
        firstContactInfo: state.firstContactInfo,
      );
    }
  }

  void flushLists() {
    _listWriteTimer?.cancel();
    _listWriteTimer = null;
    if (!_listDirty) return;
    final dir = _directory;
    if (dir == null) return;
    try {
      dir.createSync(recursive: true);
      for (final entry in _lists.entries) {
        final encoded = jsonEncode({
          'chats': [for (final chat in entry.value) encodeChatSummary(chat)],
        });
        File(_listPath(dir, entry.key)).writeAsStringSync(encoded);
      }
      _listDirty = false;
    } catch (_) {}
  }

  void flushTranscripts() {
    _transcriptWriteTimer?.cancel();
    _transcriptWriteTimer = null;
    if (!_transcriptDirty) return;
    final dir = _directory;
    if (dir == null) return;
    try {
      dir.createSync(recursive: true);
      final encoded = jsonEncode({
        'transcripts': [
          for (final entry in _transcripts.entries)
            {
              'key': entry.key,
              'anchoredHistory': entry.value.state.anchoredHistory,
              'olderHistoryExhausted': entry.value.state.olderHistoryExhausted,
              'firstContactInfo': encodeFirstContact(
                entry.value.state.firstContactInfo,
              ),
              'messages': [
                for (final message in entry.value.state.messages)
                  encodeChatMessage(message),
              ],
              if (entry.value.scroll != null)
                'scroll': entry.value.scroll!.toJson(),
            },
        ],
      });
      File(_transcriptPath(dir)).writeAsStringSync(encoded);
      _transcriptDirty = false;
    } catch (_) {}
  }

  void _loadListsFromDisk() {
    final dir = _directory;
    if (dir == null || !dir.existsSync()) return;
    try {
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.isEmpty
            ? file.path
            : file.uri.pathSegments.last;
        if (!name.startsWith('qingliao_chat_list_') ||
            !name.endsWith('.json')) {
          continue;
        }
        final slot = int.tryParse(
          name.substring('qingliao_chat_list_'.length, name.length - 5),
        );
        if (slot == null) continue;
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is! Map) continue;
        final chats = raw['chats'];
        if (chats is! List) continue;
        _lists[slot] = [
          for (final item in chats)
            if (item is Map) decodeChatSummary(Map<String, dynamic>.from(item)),
        ];
      }
    } catch (_) {}
  }

  void _loadTranscriptsFromDisk() {
    final dir = _directory;
    if (dir == null) return;
    final file = File(_transcriptPath(dir));
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return;
      final items = raw['transcripts'];
      if (items is! List) return;
      for (final item in items) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final key = map['key']?.toString() ?? '';
        if (key.isEmpty) continue;
        final messagesRaw = map['messages'];
        final messages = <ChatMessage>[
          if (messagesRaw is List)
            for (final message in messagesRaw)
              if (message is Map)
                decodeChatMessage(Map<String, dynamic>.from(message)),
        ];
        _transcripts[key] = _StoredTranscript(
          state: ChatSessionRenderState(
            messages: List<ChatMessage>.unmodifiable(messages),
            anchoredHistory: map['anchoredHistory'] == true,
            olderHistoryExhausted: map['olderHistoryExhausted'] == true,
            firstContactInfo: decodeFirstContact(map['firstContactInfo']),
          ),
          scroll: ChatSessionScrollSnapshot.fromJson(map['scroll']),
        );
      }
    } catch (_) {}
  }

  String _listPath(Directory dir, int slot) =>
      '${dir.path}/qingliao_chat_list_$slot.json';

  String _transcriptPath(Directory dir) =>
      '${dir.path}/qingliao_chat_transcripts.json';

  String _key(int accountSlot, int chatId, int? forumTopicId) =>
      '$accountSlot:$chatId:${forumTopicId ?? 0}';

  ({int accountSlot, int chatId, int? forumTopicId})? _parseKey(String key) {
    final parts = key.split(':');
    if (parts.length != 3) return null;
    final slot = int.tryParse(parts[0]);
    final chatId = int.tryParse(parts[1]);
    final topic = int.tryParse(parts[2]);
    if (slot == null || chatId == null || topic == null) return null;
    return (
      accountSlot: slot,
      chatId: chatId,
      forumTopicId: topic == 0 ? null : topic,
    );
  }
}

class _StoredTranscript {
  const _StoredTranscript({required this.state, this.scroll});

  final ChatSessionRenderState state;
  final ChatSessionScrollSnapshot? scroll;
}
