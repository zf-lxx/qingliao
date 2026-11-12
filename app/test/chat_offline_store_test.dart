import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/chat/chat_first_contact_info.dart';
import 'package:qingliao/chat/chat_offline_codec.dart';
import 'package:qingliao/chat/chat_offline_store.dart';
import 'package:qingliao/chat/chat_session_cache.dart';
import 'package:qingliao/chats/chat_list_view_model.dart';
import 'package:qingliao/tdlib/td_models.dart';

ChatMessage _message(int id, {String text = 'hello'}) =>
    ChatMessage(id: id, isOutgoing: id.isEven, text: text, date: id);

ChatSummary _summary({
  required int id,
  required String title,
  int unread = 0,
  int order = 10,
  String preview = 'last line',
}) => ChatSummary(
  id: id,
  title: title,
  lastMessage: preview,
  lastMessageId: id * 10,
  date: 1700000000 + id,
  unreadCount: unread,
  lastReadInboxMessageId: 1,
  lastReadOutboxMessageId: 2,
  order: order,
  isMuted: false,
  kind: ChatKind.privateChat,
  photo: TdFileRef(id: id, localPath: '/tmp/avatar-$id.jpg'),
);

void main() {
  late Directory dir;

  setUp(() {
    ChatOfflineStore.instance.resetForTesting();
    dir = Directory.systemTemp.createTempSync('qingliao-offline-');
    ChatOfflineStore.instance.preloadSync(dir);
  });

  tearDown(() {
    ChatOfflineStore.instance.resetForTesting();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('round-trips a chat list snapshot through disk', () {
    final original = [
      _summary(id: 11, title: 'Alice', unread: 3, preview: 'see you'),
      _summary(id: 12, title: 'Design', unread: 0, order: 9),
    ];
    ChatOfflineStore.instance.rememberList(0, original);
    ChatOfflineStore.instance.flushLists();

    ChatOfflineStore.instance.resetForTesting();
    ChatOfflineStore.instance.preloadSync(dir);

    final restored = ChatOfflineStore.instance.listSnapshot(0);
    expect(restored.map((chat) => chat.id), [11, 12]);
    expect(restored.first.title, 'Alice');
    expect(restored.first.lastMessage, 'see you');
    expect(restored.first.unreadCount, 3);
    expect(restored.first.photo?.localPath, '/tmp/avatar-11.jpg');
  });

  test('list view model paints the stored rows before any network load', () {
    ChatOfflineStore.instance.rememberList(0, [
      _summary(id: 21, title: 'Bob', unread: 5),
    ]);
    final model = ChatListViewModel();
    addTearDown(model.dispose);

    expect(model.isInitialLoading, isFalse);
    expect(model.chats, isNotEmpty);
    expect(model.chats.single.title, 'Bob');
    expect(model.chats.single.unreadCount, 5);
  });

  test('round-trips a transcript and scroll snapshot', () {
    final state = ChatSessionRenderState(
      messages: [
        _message(1, text: 'ping'),
        _message(2, text: 'pong'),
      ],
      anchoredHistory: false,
      olderHistoryExhausted: true,
      firstContactInfo: const ChatFirstContactInfo(
        countryCode: 'CN',
        registrationMonth: 4,
        registrationYear: 2024,
      ),
    );
    ChatOfflineStore.instance.rememberTranscript(
      accountSlot: 0,
      chatId: 42,
      state: state,
      scroll: const ChatSessionScrollSnapshot(
        pixels: 180,
        wasAtLoadedBottom: false,
        knownLatestMessageId: 2,
        anchorMessageId: 1,
        anchorViewportOffset: 24,
      ),
    );
    ChatOfflineStore.instance.flushTranscripts();

    ChatOfflineStore.instance.resetForTesting();
    ChatOfflineStore.instance.preloadSync(dir);

    final restored = ChatOfflineStore.instance.transcriptSnapshot(
      accountSlot: 0,
      chatId: 42,
    );
    expect(restored?.messages.map((message) => message.text), ['ping', 'pong']);
    expect(restored?.olderHistoryExhausted, isTrue);
    expect(restored?.firstContactInfo?.countryCode, 'CN');
    final scroll = ChatOfflineStore.instance.scrollSnapshot(
      accountSlot: 0,
      chatId: 42,
    );
    expect(scroll?.pixels, 180);
    expect(scroll?.anchorMessageId, 1);
    expect(scroll?.wasAtLoadedBottom, isFalse);

    final cache = ChatSessionCache();
    ChatOfflineStore.instance.hydrateSessionCache(cache);
    expect(cache.read(accountSlot: 0, chatId: 42)?.messages.last.text, 'pong');
  });

  test('codec keeps image placeholder dimensions', () {
    final encoded = encodeChatMessage(
      ChatMessage(
        id: 9,
        isOutgoing: false,
        text: '',
        date: 9,
        contentType: 'messagePhoto',
        image: TdFileRef(id: 99, localPath: '/tmp/pic.jpg'),
        imageWidth: 240,
        imageHeight: 160,
      ),
    );
    final decoded = decodeChatMessage(encoded);
    expect(decoded.imageWidth, 240);
    expect(decoded.imageHeight, 160);
    expect(decoded.image?.localPath, '/tmp/pic.jpg');
    expect(decoded.contentType, 'messagePhoto');
  });
}
