// Local HTTP / SOCKS5 proxy for the 轻聊 client.
// MTProto and Web proxies are not implemented and must stay hidden.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class QlProxyConfig {
  const QlProxyConfig({
    required this.id,
    required this.host,
    required this.port,
    required this.type,
    this.username = '',
    this.password = '',
    this.enabled = false,
    this.lastUsedDate = 0,
  });

  final int id;
  final String host;
  final int port;
  final String type; // http | socks5
  final String username;
  final String password;
  final bool enabled;
  final int lastUsedDate;

  bool get isSocks => type == 'socks5';
  bool get isHttp => type == 'http';

  QlProxyConfig copyWith({
    int? id,
    String? host,
    int? port,
    String? type,
    String? username,
    String? password,
    bool? enabled,
    int? lastUsedDate,
  }) => QlProxyConfig(
    id: id ?? this.id,
    host: host ?? this.host,
    port: port ?? this.port,
    type: type ?? this.type,
    username: username ?? this.username,
    password: password ?? this.password,
    enabled: enabled ?? this.enabled,
    lastUsedDate: lastUsedDate ?? this.lastUsedDate,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'port': port,
    'type': type,
    'username': username,
    'password': password,
    'enabled': enabled,
    'last_used_date': lastUsedDate,
  };

  factory QlProxyConfig.fromJson(Map<String, dynamic> raw) => QlProxyConfig(
    id: (raw['id'] as num?)?.toInt() ?? 0,
    host: raw['host']?.toString() ?? '',
    port: (raw['port'] as num?)?.toInt() ?? 0,
    type: raw['type']?.toString() ?? 'socks5',
    username: raw['username']?.toString() ?? '',
    password: raw['password']?.toString() ?? '',
    enabled: raw['enabled'] == true,
    lastUsedDate: (raw['last_used_date'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toTd() => {
    '@type': 'proxy',
    'id': id,
    'server': host,
    'port': port,
    'last_used_date': lastUsedDate,
    'is_enabled': enabled,
    'type': isHttp
        ? {
            '@type': 'proxyTypeHttp',
            'username': username,
            'password': password,
            'http_only': false,
          }
        : {
            '@type': 'proxyTypeSocks5',
            'username': username,
            'password': password,
          },
  };
}

/// Applies an HTTP or SOCKS5 proxy to a Dart [HttpClient].
void qlApplyProxy(HttpClient http, QlProxyConfig? proxy) {
  http.findProxy = null;
  http.connectionFactory = null;
  http.authenticate = null;
  http.authenticateProxy = null;
  if (proxy == null || proxy.host.isEmpty || proxy.port <= 0) {
    http.findProxy = (_) => 'DIRECT';
    return;
  }
  if (proxy.isHttp) {
    http.findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}';
    if (proxy.username.isNotEmpty) {
      http.addProxyCredentials(
        proxy.host,
        proxy.port,
        '轻聊',
        HttpClientBasicCredentials(proxy.username, proxy.password),
      );
    }
    return;
  }
  // SOCKS5 is not a first-class HttpClient proxy. Go DIRECT and tunnel
  // every connection through the handshake ourselves.
  http.findProxy = (_) => 'DIRECT';
  http.connectionFactory = (uri, proxyHost, proxyPort) {
    final destHost = uri.host;
    final destPort = uri.port == 0
        ? (uri.scheme == 'https' || uri.scheme == 'wss' ? 443 : 80)
        : uri.port;
    final future = qlSocks5Connect(
      proxyHost: proxy.host,
      proxyPort: proxy.port,
      destHost: destHost,
      destPort: destPort,
      username: proxy.username,
      password: proxy.password,
    );
    return Future.value(ConnectionTask.fromSocket(future, () {}));
  };
}


Future<Socket> qlSocks5Connect({
  required String proxyHost,
  required int proxyPort,
  required String destHost,
  required int destPort,
  String username = '',
  String password = '',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
  final reader = _SockReader(socket);
  try {
    final user = utf8.encode(username);
    final pass = utf8.encode(password);
    final useAuth = user.isNotEmpty;
    socket.add(useAuth ? [0x05, 0x01, 0x02] : [0x05, 0x01, 0x00]);
    final method = await reader.readExact(2, timeout);
    if (method[0] != 0x05) {
      throw const SocketException('SOCKS5 代理握手失败');
    }
    if (method[1] == 0x02) {
      if (user.length > 255 || pass.length > 255) {
        throw const SocketException('SOCKS5 用户名或密码过长');
      }
      socket.add([0x01, user.length, ...user, pass.length, ...pass]);
      final auth = await reader.readExact(2, timeout);
      if (auth[1] != 0x00) {
        throw const SocketException('SOCKS5 代理认证失败');
      }
    } else if (method[1] != 0x00) {
      throw const SocketException('SOCKS5 代理不支持当前认证方式');
    }
    final host = utf8.encode(destHost);
    if (host.isEmpty || host.length > 255) {
      throw const SocketException('SOCKS5 目标主机无效');
    }
    socket.add([
      0x05,
      0x01,
      0x00,
      0x03,
      host.length,
      ...host,
      (destPort >> 8) & 0xff,
      destPort & 0xff,
    ]);
    final head = await reader.readExact(4, timeout);
    if (head[1] != 0x00) {
      throw SocketException('SOCKS5 代理无法连接目标（状态 ${head[1]}）');
    }
    switch (head[3]) {
      case 0x01:
        await reader.readExact(4 + 2, timeout);
      case 0x03:
        final len = (await reader.readExact(1, timeout))[0];
        await reader.readExact(len + 2, timeout);
      case 0x04:
        await reader.readExact(16 + 2, timeout);
      default:
        throw const SocketException('SOCKS5 代理返回了无法解析的地址');
    }
    await reader.detach();
    return socket;
  } catch (e) {
    await reader.detach();
    socket.destroy();
    rethrow;
  }
}

class _SockReader {
  _SockReader(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buf.add(data);
        _check();
      },
      onError: (Object e, StackTrace st) {
        if (!(_pending?.isCompleted ?? true)) {
          _pending!.completeError(e, st);
        }
      },
      onDone: () {
        if (!(_pending?.isCompleted ?? true)) {
          _pending!.completeError(const SocketException('SOCKS5 代理连接已关闭'));
        }
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  Completer<void>? _pending;
  int _need = 0;

  void _check() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted && _buf.length >= _need) {
      pending.complete();
    }
  }

  Future<Uint8List> readExact(int n, Duration timeout) async {
    _need = n;
    if (_buf.length < n) {
      _pending = Completer<void>();
      await _pending!.future.timeout(timeout, onTimeout: () {
        throw const SocketException('SOCKS5 代理读取超时');
      });
    }
    final all = _buf.takeBytes();
    final out = Uint8List.fromList(all.sublist(0, n));
    if (all.length > n) _buf.add(all.sublist(n));
    return out;
  }

  Future<void> detach() async {
    if (_buf.length != 0) {
      throw const SocketException('SOCKS5 代理在握手后仍有未处理数据');
    }
    await _sub.cancel();
  }
}
