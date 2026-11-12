import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/tdlib/td_bindings.dart';
import 'package:qingliao/tdlib/td_session_string.dart';

void main() {
  test('qingliao session strings round-trip through the TDLib packing', () {
    final dir = Directory.systemTemp.createTempSync('ql-session-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File('${dir.path}/qingliao_session.json').writeAsStringSync(jsonEncode({
      'server': 'https://qingliao.zhufu.de5.net',
      'token': 'test-token',
      'user_id': 'user-abc',
      'handle': 'alice',
      'device_id': 'dev-1',
    }));
    File('${dir.path}/td.binlog').writeAsBytesSync(utf8.encode('QLSESS01'));

    const apiId = 1;
    const userId = 42;
    final bindings = TdBindings.open();
    final packed = bindings.exportSessionString(
      '${dir.path}/td.binlog',
      apiId: apiId,
      testMode: false,
      userId: userId,
    );
    final decoded = TdSessionString.decode(packed);
    expect(decoded.apiId, apiId);
    expect(decoded.userId, userId);

    final dest = Directory.systemTemp.createTempSync('ql-import-');
    addTearDown(() {
      if (dest.existsSync()) dest.deleteSync(recursive: true);
    });
    bindings.importSessionString(packed, '${dest.path}/td.binlog');
    final restored = jsonDecode(
      File('${dest.path}/qingliao_session.json').readAsStringSync(),
    ) as Map;
    expect(restored['token'], 'test-token');
    expect(restored['user_id'], 'user-abc');
    expect(restored['handle'], 'alice');
    expect(restored['server'], 'https://qingliao.zhufu.de5.net');
  });
}
