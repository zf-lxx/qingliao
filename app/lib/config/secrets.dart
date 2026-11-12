//
//  secrets.dart — 轻聊 build. Telegram API credentials are not used: the
//  TDLib layer is replaced by the pure-Dart Qingliao engine, which ignores
//  api_id/api_hash. These placeholders only satisfy the original call sites.
//
class Secrets {
  static const int apiId = 1;
  static const String apiHash = 'qingliao';
  static bool get isConfigured => true;
}
