//
//  ql_bots_view.dart — Create and manage 轻聊 bots. The token is shown once.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'ql_api.dart';

class QlBotsView extends StatefulWidget {
  const QlBotsView({super.key});

  @override
  State<QlBotsView> createState() => _QlBotsViewState();
}

class _QlBotsViewState extends State<QlBotsView> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await TdClient.shared.query({'@type': 'qlListBots'});
      final list = raw['bots'];
      setState(() {
        _bots = [
          if (list is List)
            for (final item in list)
              if (item is Map) Map<String, dynamic>.from(item),
        ];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _create() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final raw = await TdClient.shared.query({
        '@type': 'qlCreateBot',
        'username': _username.text.trim(),
        'display_name': _name.text.trim(),
      });
      final token = raw['token']?.toString() ?? '';
      _username.clear();
      _name.clear();
      await _reload();
      if (mounted && token.isNotEmpty) {
        await _showToken(token, once: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revoke(String id) async {
    try {
      final raw = await TdClient.shared.query({
        '@type': 'qlRevokeBotToken',
        'bot_id': id,
      });
      final token = raw['token']?.toString() ?? '';
      if (mounted && token.isNotEmpty) {
        await _showToken(token, once: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _delete(String id) async {
    try {
      await TdClient.shared.query({'@type': 'qlDeleteBot', 'bot_id': id});
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _showToken(String token, {required bool once}) async {
    final endpoint = '$qlDefaultServer/bot<token>/<method>';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          title: const Text('机器人令牌（只显示一次）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请立即复制并妥善保存。关闭后无法再查看完整令牌。接口根地址：',
                style: AppTextStyle.body(c.textSecondary),
              ),
              const SizedBox(height: 8),
              SelectableText(endpoint, style: AppTextStyle.body(c.textPrimary)),
              const SizedBox(height: 12),
              SelectableText(token, style: AppTextStyle.body(c.textPrimary)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
              },
              child: const Text('复制令牌'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('已保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: '机器人',
      child: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '用已登录的轻聊账号创建机器人。邀请制只约束人类注册；令牌只显示一次，服务器只保存哈希。'
              'HTTP 接口与常见 Bot API 兼容：POST $qlDefaultServer/bot<令牌>/getMe 。'
              '不要把令牌发给他人或写进聊天。',
              style: AppTextStyle.footnote(c.textSecondary),
            ),
          ),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: '用户名（以 bot 结尾，如 echo_bot）',
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    border: InputBorder.none,
                  ),
                ),
              ),
              ListTile(
                enabled: !_working,
                leading: AppIcon(HeroAppIcons.plus, color: c.textPrimary),
                title: const Text('创建机器人'),
                onTap: _working ? null : () => unawaited(_create()),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: AppTheme.unreadBadge)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: AppActivityIndicator(size: 24)),
            )
          else if (_bots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('还没有机器人', style: AppTextStyle.body(c.textSecondary)),
            )
          else
            SettingsCard(
              children: [
                for (final bot in _bots)
                  ListTile(
                    title: Text('${bot['display_name'] ?? ''}'),
                    subtitle: Text('@${bot['username'] ?? ''} · id ${bot['api_id'] ?? ''}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => unawaited(
                            _revoke(bot['id']?.toString() ?? ''),
                          ),
                          child: const Text('重置令牌'),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            _delete(bot['id']?.toString() ?? ''),
                          ),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
