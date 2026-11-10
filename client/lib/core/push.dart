import 'package:device_info_plus/device_info_plus.dart';

/// Detection is a recommendation, NOT registration. No SDK or secret is bundled.
abstract class PushChannel {
  String get provider;
  Future<String?> register();
}

class DisabledPushChannel implements PushChannel {
  @override
  String get provider => 'none';
  @override
  Future<String?> register() async => null;
}

class PushPlan {
  final String suggested, explanation;
  const PushPlan(this.suggested, this.explanation);
  static Future<PushPlan> detect() async {
    try {
      final d = await DeviceInfoPlugin().androidInfo;
      final brand = '${d.manufacturer} ${d.brand}'.toLowerCase();
      if (brand.contains('xiaomi') || brand.contains('redmi')) {
        return const PushPlan(
          'mipush',
          '检测到小米系设备。Mi Push SDK / 凭据待接入，当前仅前台连接。',
        );
      }
    } catch (_) {
      /* Unsupported host in widget tests. */
    }
    return const PushPlan('fcm', 'FCM 为候选通道（GMS 能力尚未检测），SDK / 凭据待接入。当前仅前台连接。');
  }
}
