import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/chat_engine.dart';

String replyPreview(Json? message) {
  if (message == null || message['deleted'] == true) return '消息已删除';
  final text = message['text'];
  if (text is String && text.trim().isNotEmpty) return text;
  return switch (message['kind']) {
    'image' => '图片',
    'video' => '视频',
    'voice' || 'audio' => '语音',
    'file' => '文件',
    'sticker' => '贴纸',
    _ => '消息',
  };
}

class ReplyQuote extends StatefulWidget {
  final ChatEngine engine;
  final String conversationId, messageId;
  final Json? parent;
  final int before;
  final VoidCallback onTap;
  const ReplyQuote({
    super.key,
    required this.engine,
    required this.conversationId,
    required this.messageId,
    required this.parent,
    required this.before,
    required this.onTap,
  });
  @override
  State<ReplyQuote> createState() => _ReplyQuoteState();
}

class _ReplyQuoteState extends State<ReplyQuote> {
  Future<Json?>? _lookup;
  Future<Json>? _sender;
  String? _senderId;
  Future<Uint8List>? _thumbnail;
  String? _mediaId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReplyQuote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId) {
      _lookup = null;
      _sender = null;
      _thumbnail = null;
      _senderId = null;
      _mediaId = null;
      _load();
    }
  }

  void _load() {
    if (widget.parent == null) {
      _lookup = widget.engine.resolveReply(
        widget.conversationId,
        widget.messageId,
        before: widget.before > 0 ? widget.before : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json?>(
    future: _lookup,
    initialData: widget.parent,
    builder: (context, snapshot) {
      final parent =
          widget.engine.cachedMessage(widget.messageId) ??
          widget.parent ??
          snapshot.data;
      final senderId = parent?['sender_id'] as String?;
      final deleted = parent == null || parent['deleted'] == true;
      if (!deleted && senderId != null && senderId != _senderId) {
        _senderId = senderId;
        if (widget.engine.api != null) _sender = widget.engine.user(senderId);
      }
      final mediaId = !deleted && parent['kind'] == 'image'
          ? parent['media_id'] as String?
          : null;
      if (mediaId != null &&
          mediaId.isNotEmpty &&
          mediaId != _mediaId &&
          widget.engine.api != null) {
        _mediaId = mediaId;
        _thumbnail = widget.engine.api!.media(mediaId);
      }
      const accent = Color(0xff5dade6);
      return GestureDetector(
        key: const Key('reply-quote'),
        onTap: deleted ? null : widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .07),
            border: const Border(left: BorderSide(color: accent, width: 3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!deleted && parent['kind'] == 'image') ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: _thumbnail == null
                        ? const Icon(
                            Icons.image_outlined,
                            size: 24,
                            color: accent,
                          )
                        : FutureBuilder<Uint8List>(
                            future: _thumbnail,
                            builder: (_, image) => image.hasData
                                ? Image.memory(
                                    image.data!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 90,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.image_outlined,
                                      color: accent,
                                    ),
                                  )
                                : const Icon(
                                    Icons.image_outlined,
                                    color: accent,
                                  ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!deleted)
                      FutureBuilder<Json>(
                        future: _sender,
                        initialData: widget.engine.users[senderId],
                        builder: (_, user) => Text(
                          user.data?['display_name'] ??
                              (senderId == widget.engine.uid ? '你' : '成员'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      parent == null &&
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                          ? '正在加载原消息…'
                          : snapshot.hasError && parent == null
                          ? '原消息暂时无法加载'
                          : replyPreview(parent),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
