//
//  ql_login_view.dart — 轻聊 sign-in / invite registration.
//
//  Replaces the phone-number flow: handle + password against the configured
//  server, or registration with an invite code. Built from the existing login
//  primitives (InputField, AppInteractiveSurface) so it shares their motion.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_view.dart' show InputField, ObscuringController, kLoginLaneMaxWidth;
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'ql_api.dart';

const String _serverPrefKey = 'qingliao.server';

class QlLoginView extends StatefulWidget {
  const QlLoginView({super.key});

  @override
  State<QlLoginView> createState() => _QlLoginViewState();
}

class _QlLoginViewState extends State<QlLoginView> {
  final _server = TextEditingController(text: qlDefaultServer);
  final _handle = TextEditingController();
  final _password = ObscuringController();
  final _invite = TextEditingController();
  final _name = TextEditingController();
  final _totp = TextEditingController();
  bool _register = false;
  bool _showServer = false;
  bool _working = false;
  bool _awaitingTotp = false;
  String _pendingToken = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadServer());
  }

  Future<void> _loadServer() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverPrefKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _server.text = saved);
    }
  }

  @override
  void dispose() {
    for (final c in [_server, _handle, _password, _invite, _name, _totp]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      !_working &&
      _handle.text.trim().length >= 3 &&
      _password.text.isNotEmpty &&
      (!_register || _invite.text.trim().isNotEmpty) &&
      (!_awaitingTotp || _totp.text.trim().length >= 6);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final server = qlNormalizeServer(_server.text).toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverPrefKey, server);
      if (_register && _password.text.length < 12) {
        throw const FormatException('密码至少 12 个字符');
      }
      if (_awaitingTotp) {
        await TdClient.shared.query({
          '@type': 'qlLoginTotp',
          'server': server,
          'handle': _handle.text.trim(),
          'pending_token': _pendingToken,
          'totp_code': _totp.text.trim(),
        });
        _password.clear();
        _totp.clear();
        if (mounted) {
          setState(() {
            _awaitingTotp = false;
            _pendingToken = '';
          });
        }
        return;
      }
      final result = await TdClient.shared.query({
        '@type': _register ? 'qlRegister' : 'qlLogin',
        'server': server,
        'handle': _handle.text.trim(),
        'password': _password.text,
        if (_register) 'invite_code': _invite.text.trim(),
        if (_register) 'display_name': _name.text.trim(),
      });
      if (result['@type'] == 'qlTwoFactorRequired') {
        if (mounted) {
          setState(() {
            _awaitingTotp = true;
            _pendingToken = result['pending_token']?.toString() ?? '';
            _error = null;
          });
        }
        return;
      }
      _password.clear();
    } on TdError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法连接服务器，请检查网络');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          24 + padding.left,
          padding.top + 56,
          24 + padding.right,
          AppSpacing.section + padding.bottom,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kLoginLaneMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(c),
                const SizedBox(height: 28),
                Text(
                  _register ? '用邀请码注册' : '登录轻聊',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  _register ? '轻聊目前仅限邀请注册。' : '使用你的轻聊用户名和密码登录。',
                  style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
                ),
                const SizedBox(height: 22),
                InputField(
                  systemImage: HeroAppIcons.at.data,
                  placeholder: '用户名',
                  controller: _handle,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                    LengthLimitingTextInputFormatter(32),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 12),
                InputField(
                  systemImage: HeroAppIcons.lock.data,
                  placeholder: _register ? '密码（至少 12 个字符）' : '密码',
                  controller: _password,
                  secure: true,
                  textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _register || _awaitingTotp ? null : unawaited(_submit()),
                ),
                AnimatedSize(
                  duration: AppMotion.quick,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: _awaitingTotp
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            Text(
                              '该账号已开启两步验证，请输入验证器中的 6 位验证码。',
                              style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            InputField(
                              systemImage: HeroAppIcons.shieldHalved.data,
                              placeholder: '两步验证码',
                              controller: _totp,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(8),
                              ],
                              onChanged: (_) => setState(() => _error = null),
                              onSubmitted: (_) => unawaited(_submit()),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
                AnimatedSize(
                  duration: AppMotion.quick,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: _register
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            InputField(
                              systemImage: HeroAppIcons.key.data,
                              placeholder: '邀请码',
                              controller: _invite,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() => _error = null),
                            ),
                            const SizedBox(height: 12),
                            InputField(
                              systemImage: HeroAppIcons.at.data,
                              placeholder: '昵称（可选）',
                              controller: _name,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => unawaited(_submit()),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
                AnimatedSize(
                  duration: AppMotion.quick,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: _showServer
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: InputField(
                            systemImage: HeroAppIcons.server.data,
                            placeholder: '服务器地址',
                            controller: _server,
                            keyboardType: TextInputType.url,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 14),
                  _errorBanner(c, error),
                ],
                const SizedBox(height: 20),
                _primaryButton(c),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _link(c, _register ? '已有账号？登录' : '有邀请码？注册', () {
                      setState(() {
                        _register = !_register;
                        _awaitingTotp = false;
                        _pendingToken = '';
                        _totp.clear();
                        _error = null;
                      });
                    }),
                    _link(c, _showServer ? '收起服务器' : '服务器设置', () {
                      setState(() => _showServer = !_showServer);
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand(AppColors c) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.brand,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '轻',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.onAccent),
        ),
      ),
      const SizedBox(width: AppSpacing.lg),
      Text(
        '轻聊',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary),
      ),
    ],
  );

  Widget _primaryButton(AppColors c) {
    final enabled = _canSubmit;
    final radius = BorderRadius.circular(12);
    return AppInteractiveSurface(
      semanticLabel: _awaitingTotp ? '验证并登录' : (_register ? '注册' : '登录'),
      onTap: enabled ? () => unawaited(_submit()) : null,
      enabled: enabled,
      borderRadius: radius,
      child: AnimatedOpacity(
        duration: AppMotion.quick,
        opacity: enabled || _working ? 1 : 0.4,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.brand, borderRadius: radius),
          child: _working
              ? AppActivityIndicator(size: 20, color: c.onAccent)
              : Text(
                  _awaitingTotp ? '验证并登录' : (_register ? '注册并登录' : '登录'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onAccent),
                ),
        ),
      ),
    );
  }

  Widget _link(AppColors c, String text, VoidCallback onTap) => AppInteractiveSurface(
    semanticLabel: text,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(text, style: TextStyle(fontSize: 14, color: AppTheme.brand)),
    ),
  );

  Widget _errorBanner(AppColors c, String message) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.unreadBadge.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppTheme.unreadBadge.withValues(alpha: 0.28), width: 0.8),
    ),
    child: Text(message, style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.unreadBadge)),
  );
}
