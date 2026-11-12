import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/qingliao/ql_proxy.dart';

void main() {
  test('HTTP and SOCKS5 proxies serialize to the expected TDLib shapes', () {
    const http = QlProxyConfig(
      id: 1,
      host: '127.0.0.1',
      port: 8080,
      type: 'http',
      username: 'u',
      password: 'p',
      enabled: true,
    );
    expect(http.toTd()['type'], containsPair('@type', 'proxyTypeHttp'));
    expect(http.isHttp, isTrue);

    const socks = QlProxyConfig(
      id: 2,
      host: '10.0.0.1',
      port: 1080,
      type: 'socks5',
    );
    expect(socks.toTd()['type'], containsPair('@type', 'proxyTypeSocks5'));
    expect(socks.isSocks, isTrue);

    final roundTrip = QlProxyConfig.fromJson(http.toJson());
    expect(roundTrip.host, '127.0.0.1');
    expect(roundTrip.password, 'p');
  });
}
