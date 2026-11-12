//
//  ql_api.dart — REST client for the 轻聊 Go backend (/v1).
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ql_proxy.dart';

class QlApiException implements Exception {
  const QlApiException(this.statusCode, this.error);

  final int statusCode;
  final String error;

  @override
  String toString() => 'QlApiException($statusCode, $error)';
}

const String qlDefaultServer = 'https://qingliao.zhufu.de5.net';

Uri qlNormalizeServer(String raw) {
  var text = raw.trim();
  if (text.isEmpty) text = qlDefaultServer;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.parse(text);
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const FormatException('服务器地址必须是 http(s)');
  }
  if (uri.host.isEmpty) throw const FormatException('服务器地址无效');
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(path: path, query: null, fragment: null);
}

class QlApi {
  QlApi(this.server, {this.token, QlProxyConfig? proxy}) {
    applyProxy(proxy);
  }

  final Uri server;
  String? token;
  QlProxyConfig? proxy;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  void applyProxy(QlProxyConfig? next) {
    proxy = next;
    qlApplyProxy(_http, next);
  }

  void close() => _http.close(force: true);

  /// Opens a WebSocket through the same proxy as REST calls.
  Future<WebSocket> connectWebSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) {
    return WebSocket.connect(
      uri.toString(),
      headers: headers,
      customClient: _http,
    );
  }

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = server.path;
    return server.replace(
      path: '$base/v1$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Uri get webSocketUri {
    final http = endpoint('/ws');
    return http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? q]) =>
      _json('GET', path, query: q);
  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _json('POST', path, body: body ?? const <String, dynamic>{});
  Future<Map<String, dynamic>> put(String path, [Object? body]) =>
      _json('PUT', path, body: body ?? const <String, dynamic>{});
  Future<Map<String, dynamic>> patch(String path, [Object? body]) =>
      _json('PATCH', path, body: body ?? const <String, dynamic>{});
  Future<Map<String, dynamic>> delete(String path) => _json('DELETE', path);

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final request = await _http
        .openUrl(method, endpoint(path, query))
        .timeout(const Duration(seconds: 15));
    final bearer = token;
    if (bearer != null && bearer.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );
    final text = await response.transform(utf8.decoder).join();
    return _decode(response.statusCode, text);
  }

  Map<String, dynamic> _decode(int status, String text) {
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    if (status < 200 || status >= 300) {
      final error = decoded is Map ? decoded['error']?.toString() : null;
      throw QlApiException(status, error ?? 'http_$status');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  /// Uploads a local file as raw bytes. [conversationId] binds the media to a
  /// conversation (required for message attachments; omitted for avatars).
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    String? conversationId,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(path);
    final total = await file.length();
    final request = await _http
        .postUrl(endpoint('/media'))
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.binary;
    if (conversationId != null) {
      request.headers.set('X-Conversation-ID', conversationId);
    }
    if (headers != null) {
      for (final e in headers.entries) {
        if (e.value.isNotEmpty) request.headers.set(e.key, e.value);
      }
    }
    request.contentLength = total;
    var sent = 0;
    await request.addStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      }),
    );
    final response = await request.close().timeout(
      const Duration(minutes: 5),
    );
    final text = await response.transform(utf8.decoder).join();
    return _decode(response.statusCode, text);
  }

  /// Streams GET /media/{id} into [destination]. Returns the byte count.
  Future<int> downloadMedia(
    String mediaId,
    String destination, {
    void Function(int received, int total)? onProgress,
  }) => downloadPath('/media/$mediaId', destination, onProgress: onProgress);

  /// Streams a GET under /v1[path] into [destination]. Returns the byte count.
  Future<int> downloadPath(
    String path,
    String destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = await _http
        .getUrl(endpoint(path))
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw QlApiException(response.statusCode, 'media_download_failed');
    }
    final total = response.contentLength;
    final partial = File('$destination.part');
    await partial.parent.create(recursive: true);
    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await partial.rename(destination);
    return received;
  }
}
