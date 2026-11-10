import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/core/chat_engine.dart';
import 'package:qingliao/core/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine_live_test.dart' show MemoryVault, eventually;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('public HK connection using production engine', () async {
    sqfliteFfiInit();
    final entries = File(Platform.environment['QINGLIAO_TEST_CREDENTIALS']!)
        .readAsLinesSync();
    String field(String name) => entries
        .firstWhere((x) => x.startsWith(name))
        .split(RegExp('[:：]'))
        .skip(1)
        .join(':')
        .trim();
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final engine = ChatEngine(store, MemoryVault());
    try {
      await engine.authenticate(
        'https://qingliao.zhufu.de5.net',
        field('用户名'),
        field('密码'),
      );
      await eventually(
        () => engine.online,
        reason: 'public hello/resume',
        seconds: 18,
      );
    } finally {
      await engine.shutdown();
      await store.close();
    }
  }, skip: !Platform.environment.containsKey('QINGLIAO_TEST_CREDENTIALS'));
}
