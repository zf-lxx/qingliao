// Stable message-id mapping used by the 轻聊 TDLib adapter.
//
// Conversation seqs are shifted so a TDLib message_id is never confused with
// a raw backend seq. Reply quotes must fall through a missing/zero
// reply_to_seq to a previously indexed backend id; `_int(0) ?? ref` would
// otherwise stick at 0 and a text reply could not jump to its original.

int qlMessageId(int seq) => seq << 20;
int qlSeqOf(int messageId) => messageId >> 20;

int qlReplyMessageId({int? replyToSeq, int? refSeq}) {
  final seq = (replyToSeq != null && replyToSeq > 0) ? replyToSeq : refSeq;
  if (seq == null || seq <= 0) return 0;
  return qlMessageId(seq);
}
