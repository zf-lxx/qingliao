import '../tdlib/td_models.dart';
import 'chat_first_contact_info.dart';

const _chatKindNames = {
  ChatKind.privateChat: 'privateChat',
  ChatKind.group: 'group',
  ChatKind.channel: 'channel',
  ChatKind.bot: 'bot',
  ChatKind.secret: 'secret',
  ChatKind.unknown: 'unknown',
};

ChatKind decodeChatKind(Object? raw) {
  switch (raw?.toString()) {
    case 'privateChat':
      return ChatKind.privateChat;
    case 'group':
      return ChatKind.group;
    case 'channel':
      return ChatKind.channel;
    case 'bot':
      return ChatKind.bot;
    case 'secret':
      return ChatKind.secret;
    default:
      return ChatKind.unknown;
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  return fallback;
}

String? _asString(Object? value) => value?.toString();

Map<String, dynamic>? encodeFileRef(TdFileRef? file) {
  if (file == null) return null;
  return {
    'id': file.id,
    if (file.localPath != null) 'localPath': file.localPath,
    if (file.fileName != null) 'fileName': file.fileName,
    if (file.mimeType != null) 'mimeType': file.mimeType,
    if (file.size != null) 'size': file.size,
    if (file.photoId != null) 'photoId': file.photoId,
    'hasAnimation': file.hasAnimation,
    if (file.thumbnail != null) 'thumbnail': encodeFileRef(file.thumbnail),
  };
}

TdFileRef? decodeFileRef(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  return TdFileRef(
    id: _asInt(map['id']) ?? 0,
    localPath: _asString(map['localPath']),
    fileName: _asString(map['fileName']),
    mimeType: _asString(map['mimeType']),
    size: _asInt(map['size']),
    photoId: _asInt(map['photoId']),
    hasAnimation: _asBool(map['hasAnimation']),
    thumbnail: decodeFileRef(map['thumbnail']),
  );
}

Map<String, dynamic> encodeChatSummary(ChatSummary chat) {
  return {
    'id': chat.id,
    'title': chat.title,
    'lastMessage': chat.lastMessage,
    'lastMessageId': chat.lastMessageId,
    'date': chat.date,
    'unreadCount': chat.unreadCount,
    'lastReadInboxMessageId': chat.lastReadInboxMessageId,
    'lastReadOutboxMessageId': chat.lastReadOutboxMessageId,
    'unreadMentionCount': chat.unreadMentionCount,
    'unreadReactionCount': chat.unreadReactionCount,
    'order': chat.order,
    'isMuted': chat.isMuted,
    'kind': _chatKindNames[chat.kind] ?? 'unknown',
    if (encodeFileRef(chat.photo) case final photo?) 'photo': photo,
    if (chat.lastSender != null) 'lastSender': chat.lastSender,
    'isPinned': chat.isPinned,
    'isVerified': chat.isVerified,
    'archiveOrder': chat.archiveOrder,
    'isMarkedUnread': chat.isMarkedUnread,
    'draftText': chat.draftText,
    if (chat.peerUserId != null) 'peerUserId': chat.peerUserId,
    'peerIsContact': chat.peerIsContact,
    if (chat.peerPhoneNumber != null) 'peerPhoneNumber': chat.peerPhoneNumber,
    'peerIsPremium': chat.peerIsPremium,
    'peerAccentColorId': chat.peerAccentColorId,
    'peerEmojiStatusId': chat.peerEmojiStatusId,
    'isForum': chat.isForum,
    'supportsBotTopics': chat.supportsBotTopics,
    'isSavedMessages': chat.isSavedMessages,
    if (chat.folderIds.isNotEmpty) 'folderIds': chat.folderIds.toList(),
  };
}

ChatSummary decodeChatSummary(Map<String, dynamic> raw) {
  final chat = ChatSummary(
    id: _asInt(raw['id']) ?? 0,
    title: _asString(raw['title']) ?? '',
    lastMessage: _asString(raw['lastMessage']) ?? '',
    lastMessageId: _asInt(raw['lastMessageId']) ?? 0,
    date: _asInt(raw['date']) ?? 0,
    unreadCount: _asInt(raw['unreadCount']) ?? 0,
    lastReadInboxMessageId: _asInt(raw['lastReadInboxMessageId']) ?? 0,
    lastReadOutboxMessageId: _asInt(raw['lastReadOutboxMessageId']) ?? 0,
    unreadMentionCount: _asInt(raw['unreadMentionCount']) ?? 0,
    unreadReactionCount: _asInt(raw['unreadReactionCount']) ?? 0,
    order: _asInt(raw['order']) ?? 0,
    isMuted: _asBool(raw['isMuted']),
    kind: decodeChatKind(raw['kind']),
    photo: decodeFileRef(raw['photo']),
    lastSender: _asString(raw['lastSender']),
    isPinned: _asBool(raw['isPinned']),
    isVerified: _asBool(raw['isVerified']),
    archiveOrder: _asInt(raw['archiveOrder']) ?? 0,
    isMarkedUnread: _asBool(raw['isMarkedUnread']),
    draftText: _asString(raw['draftText']) ?? '',
    peerUserId: _asInt(raw['peerUserId']),
    peerIsContact: _asBool(raw['peerIsContact']),
    peerPhoneNumber: _asString(raw['peerPhoneNumber']),
    peerIsPremium: _asBool(raw['peerIsPremium']),
    peerAccentColorId: _asInt(raw['peerAccentColorId']) ?? -1,
    peerEmojiStatusId: _asInt(raw['peerEmojiStatusId']) ?? 0,
    isForum: _asBool(raw['isForum']),
    supportsBotTopics: _asBool(raw['supportsBotTopics']),
    isSavedMessages: _asBool(raw['isSavedMessages']),
  );
  final folders = raw['folderIds'];
  if (folders is List) {
    for (final id in folders) {
      final folderId = _asInt(id);
      if (folderId != null) chat.folderIds.add(folderId);
    }
  }
  return chat;
}

Map<String, dynamic>? encodeEntity(MessageTextEntity entity) {
  return {
    'offset': entity.offset,
    'length': entity.length,
    'type': entity.type,
    if (entity.url != null) 'url': entity.url,
    if (entity.userId != null) 'userId': entity.userId,
    if (entity.customEmojiId != null) 'customEmojiId': entity.customEmojiId,
    if (entity.language != null) 'language': entity.language,
  };
}

MessageTextEntity? decodeEntity(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  return MessageTextEntity(
    offset: _asInt(map['offset']) ?? 0,
    length: _asInt(map['length']) ?? 0,
    type: _asString(map['type']) ?? '',
    url: _asString(map['url']),
    userId: _asInt(map['userId']),
    customEmojiId: _asInt(map['customEmojiId']),
    language: _asString(map['language']),
  );
}

List<Map<String, dynamic>> encodeEntities(List<MessageTextEntity> entities) => [
  for (final entity in entities) encodeEntity(entity)!,
];

List<MessageTextEntity> decodeEntities(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (decodeEntity(item) case final entity?) entity,
  ];
}

Map<String, dynamic> encodeChatMessage(ChatMessage message) {
  return {
    'id': message.id,
    'isOutgoing': message.isOutgoing,
    'text': message.text,
    'date': message.date,
    if (message.chatId != null) 'chatId': message.chatId,
    if (message.forumTopicId != null) 'forumTopicId': message.forumTopicId,
    if (message.senderName != null) 'senderName': message.senderName,
    'senderIsChat': message.senderIsChat,
    'isService': message.isService,
    if (message.contentType != null) 'contentType': message.contentType,
    if (message.senderId != null) 'senderId': message.senderId,
    if (encodeFileRef(message.senderPhoto) case final photo?)
      'senderPhoto': photo,
    if (encodeFileRef(message.image) case final image?) 'image': image,
    if (message.imageWidth != null) 'imageWidth': message.imageWidth,
    if (message.imageHeight != null) 'imageHeight': message.imageHeight,
    if (message.document != null)
      'document': {
        'fileName': message.document!.fileName,
        'size': message.document!.size,
        'ext': message.document!.ext,
        if (encodeFileRef(message.document!.file) case final file?)
          'file': file,
      },
    if (message.music != null)
      'music': {
        'title': message.music!.title,
        if (message.music!.performer != null)
          'performer': message.music!.performer,
        'duration': message.music!.duration,
        if (encodeFileRef(message.music!.cover) case final cover?)
          'cover': cover,
        if (encodeFileRef(message.music!.file) case final file?) 'file': file,
      },
    if (encodeFileRef(message.video) case final video?) 'video': video,
    if (message.videoDuration != null) 'videoDuration': message.videoDuration,
    if (message.videoFileSize != null) 'videoFileSize': message.videoFileSize,
    'hasSpoiler': message.hasSpoiler,
    if (encodeFileRef(message.animatedSticker) case final sticker?)
      'animatedSticker': sticker,
    if (encodeFileRef(message.videoSticker) case final sticker?)
      'videoSticker': sticker,
    if (message.location != null)
      'location': {
        'latitude': message.location!.latitude,
        'longitude': message.location!.longitude,
        if (message.location!.title != null) 'title': message.location!.title,
        if (message.location!.address != null)
          'address': message.location!.address,
      },
    if (message.voice != null)
      'voice': {
        if (encodeFileRef(message.voice!.file) case final file?) 'file': file,
        'duration': message.voice!.duration,
        'waveform': message.voice!.waveform,
        'transcription': message.voice!.transcription,
      },
    if (message.contact != null)
      'contact': {
        'phoneNumber': message.contact!.phoneNumber,
        'firstName': message.contact!.firstName,
        'lastName': message.contact!.lastName,
        'vcard': message.contact!.vcard,
        'userId': message.contact!.userId,
      },
    if (message.replyToMessageId != null)
      'replyToMessageId': message.replyToMessageId,
    if (message.replyToChatId != null) 'replyToChatId': message.replyToChatId,
    if (message.replyToPreview != null)
      'replyToPreview': message.replyToPreview,
    if (message.replyToSender != null) 'replyToSender': message.replyToSender,
    if (message.replyToDate != null) 'replyToDate': message.replyToDate,
    if (encodeFileRef(message.replyToImage) case final image?)
      'replyToImage': image,
    if (message.replyToImageWidth != null)
      'replyToImageWidth': message.replyToImageWidth,
    if (message.replyToImageHeight != null)
      'replyToImageHeight': message.replyToImageHeight,
    if (message.senderRole != null) 'senderRole': message.senderRole!.name,
    if (message.senderTitle != null) 'senderTitle': message.senderTitle,
    'isEdited': message.isEdited,
    'isSending': message.isSending,
    'isSendAcknowledged': message.isSendAcknowledged,
    if (message.textEntities.isNotEmpty)
      'textEntities': encodeEntities(message.textEntities),
    if (message.forwardOrigin != null) 'forwardOrigin': message.forwardOrigin,
    'mediaAlbumId': message.mediaAlbumId,
  };
}

ChatMessage decodeChatMessage(Map<String, dynamic> raw) {
  MessageDocument? document;
  final documentRaw = raw['document'];
  if (documentRaw is Map) {
    final map = Map<String, dynamic>.from(documentRaw);
    document = MessageDocument(
      fileName: _asString(map['fileName']) ?? '',
      size: _asInt(map['size']) ?? 0,
      ext: _asString(map['ext']) ?? '',
      file: decodeFileRef(map['file']),
    );
  }
  MessageMusic? music;
  final musicRaw = raw['music'];
  if (musicRaw is Map) {
    final map = Map<String, dynamic>.from(musicRaw);
    music = MessageMusic(
      title: _asString(map['title']) ?? '',
      performer: _asString(map['performer']),
      cover: decodeFileRef(map['cover']),
      file: decodeFileRef(map['file']),
      duration: _asInt(map['duration']) ?? 0,
    );
  }
  MessageLocation? location;
  final locationRaw = raw['location'];
  if (locationRaw is Map) {
    final map = Map<String, dynamic>.from(locationRaw);
    location = MessageLocation(
      latitude: _asDouble(map['latitude']) ?? 0,
      longitude: _asDouble(map['longitude']) ?? 0,
      title: _asString(map['title']),
      address: _asString(map['address']),
    );
  }
  MessageVoice? voice;
  final voiceRaw = raw['voice'];
  if (voiceRaw is Map) {
    final map = Map<String, dynamic>.from(voiceRaw);
    voice = MessageVoice(
      file: decodeFileRef(map['file']),
      duration: _asInt(map['duration']) ?? 0,
      waveform: _asString(map['waveform']) ?? '',
      transcription: _asString(map['transcription']) ?? '',
    );
  }
  MessageContactCard? contact;
  final contactRaw = raw['contact'];
  if (contactRaw is Map) {
    final map = Map<String, dynamic>.from(contactRaw);
    contact = MessageContactCard(
      phoneNumber: _asString(map['phoneNumber']) ?? '',
      firstName: _asString(map['firstName']) ?? '',
      lastName: _asString(map['lastName']) ?? '',
      vcard: _asString(map['vcard']) ?? '',
      userId: _asInt(map['userId']) ?? 0,
    );
  }
  return ChatMessage(
      id: _asInt(raw['id']) ?? 0,
      isOutgoing: _asBool(raw['isOutgoing']),
      text: _asString(raw['text']) ?? '',
      date: _asInt(raw['date']) ?? 0,
      chatId: _asInt(raw['chatId']),
      forumTopicId: _asInt(raw['forumTopicId']),
      senderName: _asString(raw['senderName']),
      senderIsChat: _asBool(raw['senderIsChat']),
      isService: _asBool(raw['isService']),
      contentType: _asString(raw['contentType']),
      senderId: _asInt(raw['senderId']),
      senderPhoto: decodeFileRef(raw['senderPhoto']),
      image: decodeFileRef(raw['image']),
      imageWidth: _asInt(raw['imageWidth']),
      imageHeight: _asInt(raw['imageHeight']),
      document: document,
      music: music,
      video: decodeFileRef(raw['video']),
      videoDuration: _asInt(raw['videoDuration']),
      videoFileSize: _asInt(raw['videoFileSize']),
      hasSpoiler: _asBool(raw['hasSpoiler']),
      animatedSticker: decodeFileRef(raw['animatedSticker']),
      videoSticker: decodeFileRef(raw['videoSticker']),
      location: location,
      voice: voice,
      contact: contact,
      replyToMessageId: _asInt(raw['replyToMessageId']),
      replyToChatId: _asInt(raw['replyToChatId']),
      replyToDate: _asInt(raw['replyToDate']),
      replyToImage: decodeFileRef(raw['replyToImage']),
      replyToImageWidth: _asInt(raw['replyToImageWidth']),
      replyToImageHeight: _asInt(raw['replyToImageHeight']),
      senderRole: _decodeMemberRole(raw['senderRole']),
      senderTitle: _asString(raw['senderTitle']),
      isEdited: _asBool(raw['isEdited']),
      isSending: _asBool(raw['isSending']),
      isSendAcknowledged: _asBool(raw['isSendAcknowledged']),
      textEntities: decodeEntities(raw['textEntities']),
      mediaAlbumId: _asInt(raw['mediaAlbumId']) ?? 0,
    )
    ..replyToPreview = _asString(raw['replyToPreview'])
    ..replyToSender = _asString(raw['replyToSender'])
    ..forwardOrigin = _asString(raw['forwardOrigin']);
}

MemberRole? _decodeMemberRole(Object? raw) {
  switch (raw?.toString()) {
    case 'owner':
      return MemberRole.owner;
    case 'admin':
      return MemberRole.admin;
    case 'member':
      return MemberRole.member;
    case 'channel':
      return MemberRole.channel;
    default:
      return null;
  }
}

Map<String, dynamic>? encodeFirstContact(ChatFirstContactInfo? info) {
  if (info == null) return null;
  return {
    'countryCode': info.countryCode,
    'registrationMonth': info.registrationMonth,
    'registrationYear': info.registrationYear,
    'isContact': info.isContact,
    'isOfficial': info.isOfficial,
  };
}

ChatFirstContactInfo? decodeFirstContact(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  return ChatFirstContactInfo(
    countryCode: _asString(map['countryCode']) ?? '',
    registrationMonth: _asInt(map['registrationMonth']) ?? 0,
    registrationYear: _asInt(map['registrationYear']) ?? 0,
    isContact: _asBool(map['isContact']),
    isOfficial: _asBool(map['isOfficial']),
  );
}

class ChatSessionScrollSnapshot {
  const ChatSessionScrollSnapshot({
    required this.pixels,
    required this.wasAtLoadedBottom,
    this.knownLatestMessageId = 0,
    this.pivotMessageId,
    this.anchorMessageId,
    this.anchorViewportOffset,
  });

  final double pixels;
  final bool wasAtLoadedBottom;
  final int knownLatestMessageId;
  final int? pivotMessageId;
  final int? anchorMessageId;
  final double? anchorViewportOffset;

  Map<String, dynamic> toJson() => {
    'pixels': pixels,
    'wasAtLoadedBottom': wasAtLoadedBottom,
    'knownLatestMessageId': knownLatestMessageId,
    if (pivotMessageId != null) 'pivotMessageId': pivotMessageId,
    if (anchorMessageId != null) 'anchorMessageId': anchorMessageId,
    if (anchorViewportOffset != null)
      'anchorViewportOffset': anchorViewportOffset,
  };

  static ChatSessionScrollSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return ChatSessionScrollSnapshot(
      pixels: _asDouble(map['pixels']) ?? 0,
      wasAtLoadedBottom: _asBool(map['wasAtLoadedBottom']),
      knownLatestMessageId: _asInt(map['knownLatestMessageId']) ?? 0,
      pivotMessageId: _asInt(map['pivotMessageId']),
      anchorMessageId: _asInt(map['anchorMessageId']),
      anchorViewportOffset: _asDouble(map['anchorViewportOffset']),
    );
  }
}
