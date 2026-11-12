/// 自己和自己的会话不出现在消息列表、搜索或联系人里，也不当作收藏入口。
bool isHiddenSelfChat({
  required int? meId,
  required int? peerUserId,
  bool isSavedMessages = false,
}) {
  if (isSavedMessages) return true;
  return meId != null && peerUserId != null && peerUserId == meId;
}
