import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

abstract class SessionVault {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> session);
  Future<void> clear();
}

class SecureSessionVault implements SessionVault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: 'qingliao.session');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  @override
  Future<void> write(Map<String, dynamic> session) =>
      _storage.write(key: 'qingliao.session', value: jsonEncode(session));
  @override
  Future<void> clear() => _storage.delete(key: 'qingliao.session');
}

/// Each state snapshot contains cache, outbox and the event cursor in ONE SQL
/// transaction. Capturing JSON before queueing prevents async mutation races.
/// This MVP favors correctness; indexed per-message tables are a later migration.
class LocalStore {
  final Database db;
  Future<void> _writes = Future.value();
  LocalStore(this.db);
  static Future<LocalStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'qingliao-v1.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE state (account TEXT PRIMARY KEY, body TEXT NOT NULL)',
        ),
      ),
    );
    return LocalStore(db);
  }

  Future<Map<String, dynamic>> load(String account) async {
    await _writes;
    final rows = await db.query(
      'state',
      where: 'account=?',
      whereArgs: [account],
    );
    return rows.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(rows.first['body'] as String));
  }

  Future<void> save(String account, Map<String, dynamic> state) {
    final body = jsonEncode(state);
    final next = _writes.then(
      (_) => db.transaction((tx) async {
        await tx.insert('state', {
          'account': account,
          'body': body,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }),
    );
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> clear(String account) async {
    await _writes;
    await db.delete('state', where: 'account=?', whereArgs: [account]);
  }

  Future<void> close() async {
    await _writes;
    await db.close();
  }
}
