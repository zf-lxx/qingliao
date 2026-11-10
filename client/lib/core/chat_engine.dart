import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'storage.dart';

typedef Json = Map<String, dynamic>;
Json obj(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};
List<Json> objects(dynamic v) => v is List ? v.map(obj).toList() : [];
int number(dynamic v) => v is num ? v.toInt() : 0;
const _uuid = Uuid();

class ChatEngine extends ChangeNotifier {
  ChatEngine(this.store, this.vault);
  final LocalStore store;
  final SessionVault vault;
  ChatApi? api;
  Json? session;
  Json me = {}, privacy = {};
  final Map<String, Json> dialogs = {}, messages = {}, outbox = {}, users = {};
  List<Json> folders = [];
  final Map<String, Map<String, int?>> readPositions = {};
  final Map<String, DateTime> typingUntil = {};
  final Map<String, List<Json>> pins = {}, reactions = {};
  int cursor = 0, badge = 0;
  bool online = false, connecting = false, closed = false, suspended = false;
  bool get signedIn => session != null;
  bool get receipts => privacy['effective'] == true;
  String get uid => session?['user_id'] ?? '';
  String get account => '${session?['server']}|$uid';
  String error = '';
  IOWebSocketChannel? _socket;
  StreamSubscription? _subscription;
  Timer? _reconnect, _heartbeat;
  int _attempt = 0, _generation = 0;
  final Map<String, Timer> _inFlight = {};
  final Map<String, DateTime> _typedAt = {};
  Future<void> _events = Future.value();

  Json snapshot() => {
    'cursor': cursor,
    'dialogs': dialogs,
    'messages': messages,
    'outbox': outbox,
    'folders': folders,
    'me': me,
    'badge': badge,
  };
  Future<void> persist() => store.save(account, snapshot());
  void restore(Json v) {
    cursor = number(v['cursor']);
    badge = number(v['badge']);
    me = obj(v['me']);
    for (final pair in [
      (dialogs, 'dialogs'),
      (messages, 'messages'),
      (outbox, 'outbox'),
    ]) {
      pair.$1
        ..clear()
        ..addAll(obj(v[pair.$2]).map((k, x) => MapEntry(k, obj(x))));
    }
    folders = objects(v['folders']);
  }

  Future<void> boot() async {
    session = await vault.read();
    if (session == null) return;
    api = ChatApi(session!['server'], token: session!['access_token']);
    restore(await store.load(account));
    notifyListeners();
    unawaited(connect());
  }

  Future<void> authenticate(
    String server,
    String handle,
    String password, {
    String? invite,
    String name = '',
  }) async {
    final base = normalizeServer(server);
    final auth = ChatApi(base);
    Json result;
    try {
      result = obj(
        await auth.call(
          'POST',
          invite == null ? '/auth/login' : '/auth/register',
          {
            'handle': handle.trim(),
            'password': password,
            'platform': 'android',
            if (invite != null) 'invite_code': invite.trim(),
            if (invite != null) 'display_name': name.trim(),
          },
        ),
      );
    } finally {
      auth.close();
    }
    session = {...result, 'server': base};
    await vault.write(session!);
    api = ChatApi(base, token: result['access_token']);
    restore(await store.load(account));
    closed = false;
    suspended = false;
    notifyListeners();
    await connect();
  }

  Future<void> refreshDialogs() async {
    final all = <String, Json>{};
    String next = '';
    do {
      final data = obj(
        await api!.call(
          'GET',
          '/conversations?archived=all&limit=100${next.isEmpty ? '' : '&cursor=${Uri.encodeComponent(next)}'}',
        ),
      );
      for (final d in objects(data['conversations'])) {
        all[d['id']] = d;
      }
      badge = number(data['total_unread_badge']);
      next = data['has_more'] == true ? data['next_cursor'] ?? '' : '';
    } while (next.isNotEmpty);
    dialogs
      ..clear()
      ..addAll(all);
    folders = objects((await api!.call('GET', '/folders'))['folders']);
    await persist();
    notifyListeners();
  }

  Future<void> connect() async {
    if (closed || suspended || !signedIn || connecting || online) return;
    connecting = true;
    error = '';
    notifyListeners();
    final generation = ++_generation;
    try {
      me = obj(await api!.call('GET', '/me'));
      privacy = obj(await api!.call('GET', '/me/privacy'));
      readPositions.clear();
      await refreshDialogs();
      if (generation != _generation || closed || suspended) return;
      final channel = api!.socket();
      _socket = channel;
      await channel.ready;
      if (generation != _generation) {
        await channel.sink.close();
        return;
      }
      // Serialize frames so durable cursor always precedes ACK.
      _subscription = channel.stream.listen(
        (raw) {
          _events = _events
              .then((_) async {
                if (generation != _generation) return;
                await _frame(obj(jsonDecode(raw as String)));
              })
              .catchError((Object e) {
                _fail(e, generation);
              });
        },
        onError: (Object e) => _fail(e, generation),
        onDone: () => _fail(null, generation),
      );
    } catch (e) {
      _fail(e, generation);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _send(Json frame) {
    _socket?.sink.add(jsonEncode({'v': 1, ...frame}));
  }

  Future<void> _frame(Json f) async {
    switch (f['op']) {
      case 'hello':
        _send({
          'op': 'sync.resume',
          'req_id': 'resume',
          'after_event_seq': cursor,
        });
      case 'result':
        if (f['req_id'] == 'resume') {
          online = true;
          _attempt = 0;
          connecting = false;
          _heartbeat?.cancel();
          _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
            _send({'op': 'ping', 'req_id': 'ping'});
            retryPending();
            notifyListeners();
          });
          retryPending();
          notifyListeners();
        }
      case 'event':
        final seq = number(f['event_seq']);
        if (seq > cursor + 1) await difference();
        if (seq > cursor) await applyEvent(f);
        // Only ACK sequence delivered on THIS socket, even if REST went further.
        _send({
          'op': 'event.ack',
          'req_id': 'ack-$seq',
          'last_persisted_event_seq': seq,
        });
      case 'message.ack':
        final m = obj(f['data']);
        _upsert(m);
        _clearFlight(m['client_msg_id']);
        outbox.remove(m['client_msg_id']);
        await persist();
        notifyListeners();
      case 'typing':
        final cid = f['conversation_id'] as String;
        if (f['typing'] == true) {
          typingUntil[cid] = DateTime.now().add(const Duration(seconds: 5));
        } else {
          typingUntil.remove(cid);
        }
        notifyListeners();
        Timer(const Duration(seconds: 5), () {
          if (!closed) notifyListeners();
        });
      case 'presence':
        final id = f['user_id'] as String;
        if (users[id] != null) {
          users[id]!.addAll({
            'online': f['online'],
            'last_seen': f['last_seen'],
          });
        }
        notifyListeners();
      case 'error':
        final req = f['req_id'] as String? ?? '';
        if (req == 'resume') throw const ApiFailure(400, 'resume_failed');
        if (outbox.containsKey(req)) {
          _clearFlight(req);
          // Server-rejected messages require explicit retry, especially 429.
          outbox[req]!['status'] = 'failed';
          outbox[req]!['error'] = '发送被拒绝，请检查内容和群权限后重试';
          messages[req]?['status'] = 'failed';
          await persist();
          notifyListeners();
        }
    }
  }

  Future<void> difference() async {
    bool more;
    do {
      final r = obj(await api!.call('GET', '/sync?after=$cursor&limit=200'));
      for (final e in objects(r['events'])) {
        if (number(e['event_seq']) > cursor) await applyEvent(e);
      }
      more = r['has_more'] == true;
    } while (more);
  }

  Future<void> applyEvent(Json e) async {
    final before = jsonEncode(snapshot());
    final cid = e['conversation_id'] as String? ?? '';
    final data = obj(e['data']);
    final type = e['type'] as String? ?? '';
    try {
      if ([
        'message.created',
        'message.edited',
        'message.deleted',
      ].contains(type)) {
        _upsert(data);
        outbox.remove(data['client_msg_id']);
        _clearFlight(data['client_msg_id']);
      } else if (type == 'dialog.updated') {
        dialogs[cid] = {...?dialogs[cid], ...data};
        badge = number(data['total_unread_badge']);
        final counts = obj(data['folder_unread_counts']);
        for (final f in folders) {
          if (counts.containsKey(f['id'])) f['unread_count'] = counts[f['id']];
        }
      } else if (type == 'dialog.removed') {
        dialogs.remove(cid);
        badge = number(data['total_unread_badge']);
        messages.removeWhere((_, m) => m['conversation_id'] == cid);
        outbox.removeWhere((_, m) => m['conversation_id'] == cid);
        pins.remove(cid);
        readPositions.remove(cid);
      } else if (type == 'read.updated' && receipts) {
        (readPositions[cid] ??= {})[data['user_id']] = number(
          data['last_read_seq'],
        );
      } else if (type == 'privacy.updated') {
        privacy.addAll(data);
        readPositions.clear();
      } else if (type == 'reaction.updated') {
        final mid = data['message_id'] as String;
        final list = reactions[mid] ??= [];
        list.removeWhere(
          (r) => r['user_id'] == data['user_id'] && r['emoji'] == data['emoji'],
        );
        if (data['remove'] != true) list.add(data);
      } else if (type == 'messages.deleted') {
        for (final m in messages.values) {
          if (m['conversation_id'] == cid &&
              m['sender_id'] == data['sender_id'] &&
              number(m['conversation_seq']) <= number(data['through_seq'])) {
            m.addAll({'deleted': true, 'text': '', 'media_id': ''});
          }
        }
      }
      cursor = number(e['event_seq']);
      await persist();
    } catch (_) {
      restore(obj(jsonDecode(before)));
      rethrow;
    }
    notifyListeners();
    if ([
      'conversation.created',
      'membership.changed',
      'folder.updated',
      'folder.deleted',
    ].contains(type)) {
      unawaited(_quiet(refreshDialogs));
    }
    if (['message.pinned', 'message.unpinned', 'pins.changed'].contains(type)) {
      unawaited(_quiet(() => loadPins(cid)));
    }
  }

  void _upsert(Json m) {
    final key = (m['client_msg_id'] as String?)?.isNotEmpty == true
        ? m['client_msg_id'] as String
        : m['id'] as String;
    messages[key] = {...m, 'status': 'stored'};
  }

  List<Json> history(String cid) {
    final list = messages.values
        .where((m) => m['conversation_id'] == cid)
        .toList();
    list.sort((a, b) {
      final x = number(a['conversation_seq']),
          y = number(b['conversation_seq']);
      if (x > 0 && y > 0) return x.compareTo(y);
      if (x > 0) return -1;
      if (y > 0) return 1;
      return (a['created_at'] as String).compareTo(b['created_at'] as String);
    });
    return list;
  }

  Future<void> loadHistory(String cid, {int? before}) async {
    final r = obj(
      await api!.call(
        'GET',
        '/conversations/$cid/messages?limit=50${before == null ? '' : '&before=$before'}',
      ),
    );
    for (final m in objects(r['messages'])) {
      _upsert(m);
    }
    await persist();
    notifyListeners();
  }

  Future<void> loadMembers(String cid) async {
    final r = await api!.call('GET', '/conversations/$cid/members');
    readPositions[cid] = {
      for (final m in objects(r['members']))
        m['user_id'] as String: m['last_read_seq'] == null
            ? null
            : number(m['last_read_seq']),
    };
    notifyListeners();
  }

  Future<void> loadPins(String cid) async {
    pins[cid] = objects(
      (await api!.call('GET', '/conversations/$cid/pins'))['messages'],
    );
    notifyListeners();
  }

  Future<void> loadReactions(String mid) async {
    reactions[mid] = objects(
      (await api!.call('GET', '/messages/$mid/reactions'))['reactions'],
    );
    notifyListeners();
  }

  Future<Json> user(String id) async {
    return users[id] ??= obj(await api!.call('GET', '/users/$id'));
  }

  Future<String> title(Json d) async {
    if (d['kind'] == 'group') return d['title'] ?? '群聊';
    final members = objects(
      (await api!.call('GET', '/conversations/${d['id']}/members'))['members'],
    );
    for (final m in members) {
      if (m['user_id'] != uid) {
        final u = await user(m['user_id']);
        return u['display_name']?.toString().isNotEmpty == true
            ? u['display_name']
            : '@${u['handle']}';
      }
    }
    return '私聊';
  }

  Future<void> send(
    String cid,
    String text, {
    String kind = 'text',
    String mediaId = '',
    String replyTo = '',
    List<Json> entities = const [],
  }) async {
    final id = _uuid.v4();
    final m = <String, dynamic>{
      'id': id,
      'client_msg_id': id,
      'conversation_id': cid,
      'conversation_seq': 0,
      'sender_id': uid,
      'kind': kind,
      'text': text,
      'media_id': mediaId,
      'reply_to': replyTo,
      'entities': entities,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'deleted': false,
      'status': 'pending',
    };
    outbox[id] = m;
    messages[id] = Map.from(m);
    await persist(); // Never transmit before durable outbox write succeeds.
    notifyListeners();
    retryPending();
  }

  void retryPending() {
    if (!online) return;
    for (final entry in outbox.entries.toList()) {
      final id = entry.key, m = entry.value;
      if (_inFlight.containsKey(id) || m['status'] == 'failed') continue;
      _inFlight[id] = Timer(const Duration(seconds: 15), () {
        _clearFlight(id);
        retryPending();
      });
      _send({
        'op': 'message.send',
        'req_id': id,
        'conversation_id': m['conversation_id'],
        'client_msg_id': id,
        'payload': {
          for (final k in ['kind', 'text', 'media_id', 'reply_to', 'entities'])
            k: m[k],
        },
      });
    }
  }

  Future<void> retry(String id) async {
    outbox[id]?['status'] = 'pending';
    messages[id]?['status'] = 'pending';
    await persist();
    retryPending();
    notifyListeners();
  }

  void _clearFlight(dynamic id) {
    _inFlight.remove(id)?.cancel();
  }

  Future<void> state(String cid, Json patch) async {
    await api!.call('PATCH', '/conversations/$cid/state', patch);
  }

  Future<void> draft(String cid, String text, String reply) => state(
    cid,
    text.isEmpty && reply.isEmpty
        ? {'clear_draft': true}
        : {
            'draft': {'text': text, 'entities': [], 'reply_to': reply},
          },
  );
  Future<void> read(String cid, int seq) async {
    if (!online || seq <= number(dialogs[cid]?['last_read_seq'])) return;
    await api!.call('POST', '/conversations/$cid/read', {'last_read_seq': seq});
  }

  void typing(String cid, bool value) {
    if (!online) return;
    final now = DateTime.now();
    if (value &&
        now.difference(_typedAt[cid] ?? DateTime(2000)).inMilliseconds < 2200) {
      return;
    }
    _typedAt[cid] = now;
    _send({
      'op': 'typing',
      'req_id': 'typing',
      'conversation_id': cid,
      'typing': value,
    });
  }

  Future<void> edit(Json m, String text) async {
    await api!.call('PATCH', '/messages/${m['id']}', {
      'text': text,
      'entities': [],
    });
  }

  Future<void> recall(Json m) async {
    await api!.call('DELETE', '/messages/${m['id']}');
  }

  Future<void> react(Json m, String emoji) async {
    final remove = (reactions[m['id']] ?? []).any(
      (r) => r['user_id'] == uid && r['emoji'] == emoji,
    );
    await api!.call('PUT', '/messages/${m['id']}/reactions', {
      'emoji': emoji,
      'remove': remove,
    });
  }

  Future<void> pin(Json m, {bool remove = false}) async {
    await api!.call('PUT', '/conversations/${m['conversation_id']}/pins', {
      'message_id': m['id'],
      'remove': remove,
    });
  }

  bool isRead(Json m) =>
      receipts &&
      (readPositions[m['conversation_id']] ?? {}).entries.any(
        (e) =>
            e.key != uid &&
            e.value != null &&
            e.value! >= number(m['conversation_seq']),
      );
  Future<void> _quiet(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  void _fail(Object? e, int generation) {
    if (generation != _generation || closed || suspended) return;
    online = false;
    connecting = false;
    _heartbeat?.cancel();
    _subscription?.cancel();
    _socket?.sink.close();
    _socket = null;
    for (final t in _inFlight.values) {
      t.cancel();
    }
    _inFlight.clear();
    error = e is ApiFailure ? e.toString() : '连接中断，正在自动重连';
    if (e is ApiFailure && e.status == 401) {
      suspended = true;
      notifyListeners();
      return;
    }
    final ms =
        min(30000, 800 * pow(2, min(_attempt++, 5)).toInt()) +
        Random().nextInt(500);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(milliseconds: ms), connect);
    notifyListeners();
  }

  /// Used by lifecycle (and deterministic offline/reconnect acceptance tests).
  Future<void> disconnect({bool pause = true}) async {
    suspended = pause;
    ++_generation;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await _socket?.sink.close();
    _socket = null;
    for (final t in _inFlight.values) {
      t.cancel();
    }
    _inFlight.clear();
    await _events;
    online = false;
    connecting = false;
    notifyListeners();
  }

  Future<void> resume() async {
    suspended = false;
    await connect();
  }

  Future<void> logout({bool localOnly = false}) async {
    if (!localOnly) await api!.call('POST', '/auth/logout');
    await disconnect();
    await store.clear(account);
    await vault.clear();
    api?.close();
    api = null;
    session = null;
    restore({});
    privacy = {};
    users.clear();
    readPositions.clear();
    pins.clear();
    reactions.clear();
    notifyListeners();
  }

  Future<void> shutdown() async {
    await disconnect();
    closed = true;
    api?.close();
  }
}
