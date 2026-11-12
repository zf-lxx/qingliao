import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/bot_api/bot_api_account.dart';
import 'package:qingliao/bot_api/bot_api_endpoint_config.dart';
import 'package:qingliao/qingliao/ql_api.dart';

void main() {
  test('the default Bot API root is the 轻聊 server, without a token in the path', () {
    expect(BotApiEndpointConfig.defaultEndpoint.toString(), qlDefaultServer);
    expect(
      normalizeBotApiEndpoint(qlDefaultServer).toString(),
      'https://qingliao.zhufu.de5.net',
    );
    expect(
      () => normalizeBotApiEndpoint(
        '$qlDefaultServer/bot123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef',
      ),
      throwsFormatException,
    );
  });
}
