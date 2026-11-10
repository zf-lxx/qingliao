import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

class ApiFailure implements Exception {
  final int status;
  final String code;
  const ApiFailure(this.status, this.code);
  @override
  String toString() => switch (status) {
    401 => '登录已过期，请重新登录',
    403 => '没有操作权限，或消息不符合群规则',
    409 => '内容冲突，请刷新后重试',
    429 => '操作太频繁，请稍后手动重试',
    413 => '图片过大',
    507 => '服务器存储空间不足',
    501 => '此功能将在第二期开放',
    _ => '请求失败（$status）',
  };
}

String normalizeServer(String value) {
  final u = Uri.parse(value.trim());
  if (!u.hasAuthority ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment ||
      (u.path.isNotEmpty && u.path != '/') ||
      !['https', 'http'].contains(u.scheme)) {
    throw const FormatException('请输入服务器根地址，如 https://chat.example.com');
  }
  if (u.scheme != 'https' &&
      !['localhost', '127.0.0.1', '10.0.2.2'].contains(u.host)) {
    throw const FormatException('公网服务器必须使用 HTTPS；HTTP 仅用于本机调试');
  }
  return '${u.scheme}://${u.authority}';
}

class ChatApi {
  final String base, token;
  final http.Client client;
  ChatApi(String base, {this.token = '', http.Client? client})
    : base = normalizeServer(base),
      client = client ?? http.Client();
  Map<String, String> get headers => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  Uri uri(String path) => Uri.parse('$base/v1$path');
  Future<dynamic> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final req = http.Request(method, uri(path));
    req.headers.addAll({...headers, 'Content-Type': 'application/json'});
    if (body != null) req.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 15)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(response.statusCode, 'request_failed');
    }
    return response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  IOWebSocketChannel socket() => IOWebSocketChannel.connect(
    Uri.parse('${base.replaceFirst('http', 'ws')}/v1/ws'),
    headers: headers,
    connectTimeout: const Duration(seconds: 12),
    pingInterval: const Duration(seconds: 25),
  );
  Future<String> upload(String cid, Uint8List bytes) async {
    final r = await client
        .post(
          uri('/media'),
          headers: {
            ...headers,
            'Content-Type': 'image/jpeg',
            'X-Conversation-ID': cid,
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiFailure(r.statusCode, 'upload_failed');
    }
    return jsonDecode(r.body)['id'] as String;
  }

  Future<Uint8List> media(String id) async {
    final r = await client
        .get(uri('/media/$id'), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ApiFailure(r.statusCode, 'media_failed');
    return r.bodyBytes;
  }

  void close() => client.close();
}
