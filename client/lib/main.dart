import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

import 'core/api.dart';
import 'core/chat_engine.dart';
import 'core/storage.dart';
import 'core/push.dart';
import 'widgets/connection_title.dart';
import 'widgets/reply_quote.dart';
import 'widgets/image_viewer.dart';
import 'ui/motion/tg_motion.dart';
import 'ui/home/chat_list_widgets.dart';
import 'ui/chat/chat_widgets.dart';
import 'ui/theme/tg_tokens.dart';
import 'ui/profile/chat_info_page.dart';
import 'cells/message_layout.dart';
import 'cells/text_message_cell.dart';
import 'compositor/message_enter_transition.dart';

const bg = TgTokens.background,
    panel = TgTokens.card,
    blue = TgTokens.accent,
    muted = TgTokens.muted;
const slideCurve = Cubic(.33, .52, .25, .99);
const sendCurve = tgMessageCurve;
// Android deliberately uses the device's own font/emoji. Desktop screenshot
// tests register these aliases from Linux system fonts, never APK assets.
String? get chatFont =>
    defaultTargetPlatform == TargetPlatform.android ? null : 'ChatSans';
List<String>? get emojiFallback =>
    defaultTargetPlatform == TargetPlatform.android ? null : ['ChatEmoji'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = ChatEngine(await LocalStore.open(), SecureSessionVault());
  try {
    await engine.boot();
  } catch (_) {
    engine.error = '本地会话读取失败，请重新登录';
  }
  runApp(QingliaoApp(engine: engine));
}

class QingliaoApp extends StatefulWidget {
  final ChatEngine engine;
  const QingliaoApp({super.key, required this.engine});
  @override
  State<QingliaoApp> createState() => _QingliaoAppState();
}

class _QingliaoAppState extends State<QingliaoApp> with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _network;
  static const _networkEvents = EventChannel('xyz.qingliao.app/network');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _network = _networkEvents.receiveBroadcastStream().listen((_) {
        if (widget.engine.signedIn) unawaited(widget.engine.resume());
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _network?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.engine.signedIn) {
      unawaited(widget.engine.resume());
    }
    // Do not promise a background keepalive. Socket can be killed by Android;
    // resume always reconnects from the last DURABLE event cursor.
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '轻聊',
    debugShowCheckedModeBanner: false,
    scrollBehavior: const MaterialScrollBehavior().copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      },
    ),
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: bg,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: TgBackdropTransitions(),
          TargetPlatform.linux: TgBackdropTransitions(),
          TargetPlatform.windows: TgBackdropTransitions(),
          TargetPlatform.iOS: TgBackdropTransitions(),
          TargetPlatform.macOS: TgBackdropTransitions(),
        },
      ),
      colorScheme: const ColorScheme.dark(
        primary: blue,
        secondary: blue,
        surface: panel,
        surfaceContainerLowest: bg,
        surfaceContainerLow: panel,
        surfaceContainer: panel,
        surfaceContainerHigh: TgTokens.raised,
        surfaceContainerHighest: TgTokens.raised,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: chatFont,
        bodyColor: const Color(0xffeef4fa),
        displayColor: const Color(0xffeef4fa),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgTokens.cardRadius),
        ),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TgTokens.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgTokens.cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgTokens.smallRadius),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: AnimatedBuilder(
      animation: widget.engine,
      builder: (_, _) => widget.engine.signedIn
          ? DialogsPage(engine: widget.engine)
          : LoginPage(engine: widget.engine),
    ),
  );
}

Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiFailure
                ? e.toString()
                : e is FormatException
                ? e.message
                : '网络或本地存储暂不可用，请重试',
          ),
        ),
      );
    }
  }
}

Future<void> openLink(BuildContext context, String raw) async {
  final u = Uri.tryParse(raw);
  if (u == null ||
      !['http', 'https'].contains(u.scheme) ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty) {
    return;
  }
  final ok = await showTgDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('打开外部链接？'),
      content: Text(u.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('打开'),
        ),
      ],
    ),
  );
  if (ok == true) await launchUrl(u, mode: LaunchMode.externalApplication);
}

PageRoute<T> chatRoute<T>(Widget page) => TgPageRoute<T>(page: page);

class LoginPage extends StatefulWidget {
  final ChatEngine engine;
  const LoginPage({super.key, required this.engine});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final server = TextEditingController(),
      handle = TextEditingController(),
      password = TextEditingController(),
      invite = TextEditingController(),
      name = TextEditingController();
  bool registering = false, busy = false, hidden = true;
  String error = '';
  @override
  void dispose() {
    for (final c in [server, handle, password, invite, name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      normalizeServer(server.text);
      if (!RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(handle.text.trim())) {
        throw const FormatException('用户名需为 3–32 位字母、数字或下划线');
      }
      if (password.text.isEmpty ||
          (registering &&
              (password.text.length < 12 || invite.text.trim().isEmpty))) {
        throw const FormatException('注册需要邀请码及至少 12 位密码（最多 72 字节）');
      }
      await widget.engine.authenticate(
        server.text,
        handle.text,
        password.text,
        invite: registering ? invite.text : null,
        name: name.text,
      );
      if (mounted) {
        password.clear();
        invite.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is ApiFailure
              ? e.toString()
              : '无法连接服务器，请检查地址和网络',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xff24445e),
                  child: Icon(Icons.send_rounded, size: 35, color: blue),
                ),
                const SizedBox(height: 22),
                const Text(
                  '轻聊',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  registering ? '凭邀请，开启一段对话。' : '连接自己的服务器，继续对话。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 30),
                TextField(
                  key: const Key('server'),
                  controller: server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://chat.example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('handle'),
                  controller: handle,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('password'),
                  controller: password,
                  obscureText: hidden,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (registering) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '昵称（选填）'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('invite'),
                    controller: invite,
                    decoration: const InputDecoration(labelText: '邀请码'),
                  ),
                ],
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                const SizedBox(height: 22),
                FilledButton(
                  key: const Key('login'),
                  onPressed: busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      busy
                          ? '正在连接…'
                          : registering
                          ? '创建账号'
                          : '登录',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          registering = !registering;
                          error = '';
                        }),
                  child: Text(registering ? '已有账号？登录' : '有邀请码？注册'),
                ),
                const SizedBox(height: 20),
                const Text(
                  '内测版 · 非 Telegram 客户端\n非端到端加密，服务器可访问消息内容。\n仅前台连接；厂商推送尚未接入。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String shortTime(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return d == null
      ? ''
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class Avatar extends StatelessWidget {
  final String name;
  final double radius;
  const Avatar(this.name, {super.key, this.radius = 25});
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xff548bac),
      const Color(0xffab806c),
      const Color(0xff7d84b1),
      const Color(0xff688e80),
    ];
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors[name.hashCode.abs() % colors.length],
      child: Text(
        name.isEmpty ? '聊' : String.fromCharCode(name.runes.first),
        style: const TextStyle(color: Colors.white, fontSize: 20),
      ),
    );
  }
}

class DialogsPage extends StatefulWidget {
  final ChatEngine engine;
  const DialogsPage({super.key, required this.engine});
  @override
  State<DialogsPage> createState() => _DialogsPageState();
}

class _DialogsPageState extends State<DialogsPage> {
  int nav = 0;
  bool showCompose = true;
  void newChat() => Navigator.push(context, chatRoute(NewChatPage(engine: e)));
  void profile() => Navigator.push(context, chatRoute(ProfilePage(engine: e)));
  Widget navigationBody() {
    final users = e.users.values.where((u) => u['id'] != e.uid).toList();
    if (nav == 1) {
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded),
            title: const Text('搜索用户 / 新建群聊'),
            onTap: newChat,
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('最近联系人', style: TextStyle(color: muted)),
          ),
          for (final u in users)
            ListTile(
              leading: Avatar(u['display_name'] ?? u['handle'] ?? '?'),
              title: Text(u['display_name'] ?? u['handle'] ?? '用户'),
              subtitle: Text('@${u['handle'] ?? ''}'),
              onTap: () => guard(context, () async {
                final d = obj(
                  await e.api!.call('POST', '/conversations', {
                    'kind': 'direct',
                    'member_ids': [u['id']],
                  }),
                );
                await e.refreshDialogs();
                if (!mounted) return;
                Navigator.push(
                  context,
                  chatRoute(
                    ChatPage(
                      engine: e,
                      cid: d['id'],
                      title: u['display_name'] ?? u['handle'] ?? '用户',
                    ),
                  ),
                );
              }),
            ),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('搜索用户名开始新的聊天，常用联系人会显示在这里。'),
            ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Center(
          child: Avatar(
            e.me['display_name'] ?? e.me['handle'] ?? '我',
            radius: 44,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            e.me['display_name'] ?? e.me['handle'] ?? '我',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '@${e.me['handle'] ?? ''}',
            style: const TextStyle(color: muted),
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          tileColor: Theme.of(context).colorScheme.surfaceContainer,
          leading: const Icon(Icons.manage_accounts_rounded),
          title: Text(nav == 2 ? '账号、隐私与回执' : '编辑个人资料'),
          subtitle: const Text('昵称、简介、已读回执和退出登录'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: profile,
        ),
        const SizedBox(height: 20),
        const ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text('轻聊 0.2.0'),
          subtitle: Text('界面重绘 · 自主实现的 Telegram 风格动效'),
        ),
      ],
    );
  }

  ChatEngine get e => widget.engine;
  final Map<String, String> titles = {};
  final Set<String> fetching = {};
  bool archived = false;
  String folder = '', query = '';
  String title(Json d) {
    final id = d['id'] as String;
    if (d['kind'] == 'group') return d['title'] ?? '群聊';
    if (!titles.containsKey(id) && e.online && fetching.add(id)) {
      e
          .title(d)
          .then((t) {
            if (mounted) setState(() => titles[id] = t);
          })
          .catchError((_) {})
          .whenComplete(() => fetching.remove(id));
    }
    return titles[id] ?? d['display_title'] ?? '私聊';
  }

  bool matches(Json d) {
    if ((d['archived'] == true) != archived) return false;
    if (!title(d).toLowerCase().contains(query.toLowerCase())) return false;
    if (folder.isEmpty) return true;
    final f = e.folders.where((f) => f['id'] == folder).firstOrNull;
    if (f == null) return true;
    final filter = obj(f['filter']);
    final included = filter['include_chat_ids'] as List? ?? [],
        excluded = filter['exclude_chat_ids'] as List? ?? [],
        types = filter['types'] as List? ?? [];
    if (excluded.contains(d['id'])) return false;
    if ((included.isNotEmpty || types.isNotEmpty) &&
        !included.contains(d['id']) &&
        !types.contains(d['kind'])) {
      return false;
    }
    return filter['unread_only'] != true ||
        number(d['unread_count']) > 0 ||
        d['manual_unread'] == true;
  }

  Future<void> menu(Json d) async {
    await showTgSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title(d)), subtitle: const Text('仅修改自己的会话状态')),
            for (final action in [
              (
                'pin',
                number(d['pinned_order']) > 0 ? '取消置顶' : '置顶会话',
                Icons.push_pin_outlined,
              ),
              (
                'mute',
                number(d['notification_mute_until']) > 0 ? '取消免打扰' : '免打扰',
                Icons.notifications_off_outlined,
              ),
              ('archive', archived ? '移出归档' : '归档', Icons.archive_outlined),
              ('unread', '标为未读', Icons.mark_chat_unread_outlined),
            ])
              ListTile(
                leading: Icon(action.$3),
                title: Text(action.$2),
                onTap: () {
                  Navigator.pop(c);
                  guard(
                    context,
                    () => e.state(d['id'], switch (action.$1) {
                      'pin' => {
                        'pinned_order': number(d['pinned_order']) > 0 ? 0 : 1,
                      },
                      'mute' => {
                        'mute_until': number(d['notification_mute_until']) > 0
                            ? ''
                            : 'forever',
                      },
                      'archive' => {'archived': !archived},
                      _ => {'mark_unread': true},
                    }),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> makeFolder() async {
    final name = TextEditingController();
    final ok = await showTgDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建未读文件夹'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && mounted) {
      await guard(context, () async {
        await e.api!.call('POST', '/folders', {
          'name': name.text.trim(),
          'sort_order': e.folders.length,
          'filter': {
            'include_chat_ids': [],
            'exclude_chat_ids': [],
            'types': [],
            'unread_only': true,
          },
        });
        await e.refreshDialogs();
      });
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: e,
    builder: (context, _) {
      final items = e.dialogs.values.where(matches).toList()
        ..sort((a, b) {
          final ap = number(a['pinned_order']), bp = number(b['pinned_order']);
          if (ap > 0 || bp > 0) {
            if (ap == 0) return 1;
            if (bp == 0) return -1;
            if (ap != bp) return ap.compareTo(bp);
          }
          return number(b['last_activity'])
              .compareTo(number(a['last_activity']));
        });
      final archivedCount = e.dialogs.values
          .where((d) => d['archived'] == true)
          .length;
      final list = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: '搜索会话',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: .6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: blue.withValues(alpha: .5)),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TgFolderTabs(
                  selected: folder,
                  onSelected: (id) => setState(() => folder = id),
                  tabs: [
                    (id: '', label: '全部', count: e.badge),
                    for (final f in e.folders)
                      (
                        id: '${f['id']}',
                        label: '${f['name']}',
                        count: number(f['unread_count']),
                      ),
                  ],
                ),
              ),
              TgIconButton(
                tooltip: '新建文件夹',
                icon: Icons.add_rounded,
                onPressed: makeFolder,
                size: 38,
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (archivedCount > 0 || archived)
            ListTile(
              dense: true,
              leading: Container(
                width: 48,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  archived ? Icons.inbox_rounded : Icons.archive_rounded,
                  color: muted,
                ),
              ),
              title: Text(
                archived ? '返回全部聊天' : '已归档的聊天',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Text(
                '$archivedCount',
                style: const TextStyle(color: muted),
              ),
              onTap: () => setState(() => archived = !archived),
            ),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (n) {
                if (n.depth == 0 && (n.scrollDelta ?? 0).abs() > 3) {
                  final v = (n.scrollDelta ?? 0) < 0;
                  if (v != showCompose) setState(() => showCompose = v);
                }
                return false;
              },
              child: RefreshIndicator(
                onRefresh: e.refreshDialogs,
                child: items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 100),
                          Icon(Icons.forum_outlined, size: 50, color: muted),
                          SizedBox(height: 18),
                          Center(
                            child: Text(
                              '还没有对话，点右下角开始聊天',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length,
                        findChildIndexCallback: (key) {
                          final i = items.indexWhere(
                            (d) => ValueKey(d['id']) == key,
                          );
                          return i < 0 ? null : i;
                        },
                        itemBuilder: (context, i) {
                          final d = items[i],
                              last = obj(d['last_message']),
                              draft = obj(d['draft']);
                          final name = title(d);
                          final unread = number(d['unread_count']);
                          final isMuted =
                              number(d['notification_mute_until']) >
                              DateTime.now().millisecondsSinceEpoch ~/ 1000;
                          final preview =
                              draft['text']?.toString().isNotEmpty == true
                              ? '草稿：${draft['text']}'
                              : last['deleted'] == true
                              ? '消息已撤回'
                              : last['kind'] == 'image'
                              ? '图片 ${last['text'] ?? ''}'
                              : last['text'] ?? '开始对话';
                          return TgReorderItem(
                            key: ValueKey(d['id']),
                            index: i,
                            child: Dismissible(
                              key: ValueKey('swipe-${d['id']}'),
                              confirmDismiss: (direction) async {
                                await guard(
                                  context,
                                  () => e.state(
                                    d['id'],
                                    direction == DismissDirection.endToStart
                                        ? {'archived': d['archived'] != true}
                                        : {
                                            'manual_unread':
                                                d['manual_unread'] != true,
                                          },
                                  ),
                                );
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 24),
                                color: blue,
                                child: const Icon(
                                  Icons.mark_chat_unread_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              secondaryBackground: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: const Color(0xff7793a5),
                                child: Icon(
                                  archived
                                      ? Icons.unarchive_rounded
                                      : Icons.archive_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              child: TgChatRow(
                                avatar: Avatar(name, radius: 29),
                                title: name,
                                preview: preview,
                                time: last.isEmpty
                                    ? ''
                                    : shortTime(last['created_at']),
                                unread: unread > 0
                                    ? unread
                                    : d['manual_unread'] == true
                                    ? 1
                                    : 0,
                                muted: isMuted,
                                pinned: number(d['pinned_order']) > 0,
                                mention: number(d['unread_mention_count']) > 0,
                                outgoing:
                                    last['sender_id'] == e.uid && draft.isEmpty,
                                read:
                                    d['read_receipts_visible'] == true &&
                                    number(d['last_message_read_count']) > 0,
                                draft: draft.isNotEmpty,
                                onLongPress: () => menu(d),
                                onTap: () => Navigator.push(
                                  context,
                                  chatRoute(
                                    ChatPage(
                                      engine: e,
                                      cid: d['id'],
                                      title: name,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      );
      return Scaffold(
        extendBody: true,
        appBar: AppBar(
          toolbarHeight: 78,
          centerTitle: false,
          titleSpacing: 20,
          title: nav == 0
              ? ConnectionTitle(
                  engine: e,
                  title: archived ? '归档聊天' : '轻聊',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                )
              : Text(
                  ['轻聊', '联系人', '设置', '个人资料'][nav],
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
          actions: [
            TgIconButton(
              tooltip: '个人资料',
              icon: Icons.person_outline_rounded,
              onPressed: profile,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: nav == 0 ? list : navigationBody(),
        bottomNavigationBar: TgBottomNav(
          selected: nav,
          badge: e.badge,
          onChanged: (i) => setState(() => nav = i),
        ),
        floatingActionButton: nav == 0
            ? AnimatedSlide(
                duration: const Duration(milliseconds: 280),
                curve: Curves.decelerate,
                offset: showCompose ? Offset.zero : const Offset(0, 1.6),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 280),
                  scale: showCompose ? 1 : .7,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 280),
                    opacity: showCompose ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showCompose,
                      child: PressableScale(
                        onTap: newChat,
                        tooltip: '新建聊天',
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      );
    },
  );
}

class ChatPage extends StatefulWidget {
  final ChatEngine engine;
  final String cid, title;
  const ChatPage({
    super.key,
    required this.engine,
    required this.cid,
    required this.title,
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final Set<String> selection = {};
  void toggleSelected(Json m) {
    setState(() {
      if (!selection.add(m['id'])) selection.remove(m['id']);
    });
    HapticFeedback.selectionClick();
  }

  List<Json> get selectedMessages =>
      e.history(widget.cid).where((m) => selection.contains(m['id'])).toList();
  void copySelected() {
    Clipboard.setData(
      ClipboardData(
        text: selectedMessages
            .map((m) => m['text'] ?? replyPreview(m))
            .join('\n'),
      ),
    );
    setState(selection.clear);
  }

  void replySelected() {
    final m = selectedMessages.single;
    setState(() {
      reply = m;
      editing = null;
      selection.clear();
    });
    textChanged(input.text);
  }

  Future<void> deleteSelected() async {
    final messages = selectedMessages;
    final yes = await showTgDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('为所有人撤回 ${messages.length} 条消息？'),
        content: const Text('无法撤回此操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await guard(context, () async {
      for (final m in messages) {
        await e.recall(m);
      }
      if (mounted) setState(selection.clear);
    });
  }

  void emojiPanel() => showTgSheet(
    context: context,
    builder: (c) => Padding(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final emoji in [
            '😀',
            '😂',
            '🥰',
            '👍',
            '❤️',
            '🎉',
            '🔥',
            '🥹',
            '🙏',
            '👌',
            '✨',
            '💯',
          ])
            PressableScale(
              onTap: () {
                input.text += emoji;
                input.selection = TextSelection.collapsed(
                  offset: input.text.length,
                );
                textChanged(input.text);
                Navigator.pop(c);
              },
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 30,
                  fontFamilyFallback: emojiFallback,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  void localSearch() {
    String q = '';
    showTgSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final results = e
              .history(widget.cid)
              .where(
                (m) =>
                    q.isNotEmpty &&
                    (m['text'] ?? '').toString().toLowerCase().contains(
                      q.toLowerCase(),
                    ),
              )
              .toList();
          return SizedBox(
            height: MediaQuery.sizeOf(c).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => update(() => q = v),
                    decoration: const InputDecoration(
                      hintText: '搜索已加载的消息',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const Text(
                  '仅搜索本机已加载消息 · 云端全文搜索开发中',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final m in results)
                        ListTile(
                          title: Text(
                            m['text'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(shortTime(m['created_at'])),
                          onTap: () {
                            Navigator.pop(c);
                            jumpToReply(m['id']);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void chatMenu() {
    bool submenu = false;
    showTgPopup(
      context: context,
      itemCount: 4,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.decelerate,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(.2, 0),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(submenu),
              mainAxisSize: MainAxisSize.min,
              children: submenu
                  ? [
                      ListTile(
                        leading: const Icon(Icons.arrow_back_rounded),
                        title: const Text('静音时长'),
                        onTap: () => update(() => submenu = false),
                      ),
                      for (final item in [
                        (label: '1 小时', hours: 1),
                        (label: '8 小时', hours: 8),
                        (label: '2 天', hours: 48),
                        (label: '永久静音', hours: -1),
                        (label: '取消静音', hours: 0),
                      ])
                        ListTile(
                          title: Text(item.label),
                          onTap: () {
                            Navigator.pop(c);
                            guard(
                              context,
                              () => e.state(widget.cid, {
                                'mute_until': item.hours < 0
                                    ? 'forever'
                                    : item.hours == 0
                                    ? ''
                                    : DateTime.now()
                                          .toUtc()
                                          .add(Duration(hours: item.hours))
                                          .toIso8601String(),
                              }),
                            );
                          },
                        ),
                    ]
                  : [
                      ListTile(
                        leading: const Icon(Icons.volume_off_outlined),
                        title: const Text('静音'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => update(() => submenu = true),
                      ),
                      const Divider(height: 12, thickness: 6),
                      ListTile(
                        leading: const Icon(Icons.search_rounded),
                        title: const Text('搜索'),
                        onTap: () {
                          Navigator.pop(c);
                          localSearch();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('聊天信息'),
                        onTap: () {
                          Navigator.pop(c);
                          showInfo();
                        },
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget header(bool typing) {
    final selected = selectedMessages;
    final canRecall =
        selected.isNotEmpty &&
        selected.every(
          (m) =>
              m['sender_id'] == e.uid ||
              ['owner', 'admin'].contains(e.dialogs[widget.cid]?['role']),
        );
    final normal = Row(
      key: const ValueKey('normal'),
      children: [
        TgIconButton(
          tooltip: '返回',
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.maybePop(context),
        ),
        Expanded(
          child: PressableScale(
            onTap: showInfo,
            child: Row(
              children: [
                Hero(
                  tag: 'chat-avatar-${widget.cid}',
                  child: Avatar(widget.title, radius: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          if (typing && e.online)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: TgTypingDots(),
                            ),
                          Expanded(
                            child: ConnectionTitle(
                              engine: e,
                              title: typing
                                  ? '正在输入…'
                                  : e.online
                                  ? '已连接 · 云端聊天'
                                  : '云端聊天',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ],
    );
    final selecting = Row(
      key: const ValueKey('select'),
      children: [
        TgIconButton(
          icon: Icons.close_rounded,
          onPressed: () => setState(selection.clear),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              '已选择 ${selection.length} 项',
              key: ValueKey(selection.length),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
    final actionButtons = selection.isEmpty
        ? TgIconButton(
            tooltip: '聊天菜单',
            icon: Icons.more_vert_rounded,
            onPressed: chatMenu,
            size: 56,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.length == 1 && selected.first['sender_id'] == e.uid)
                TgIconButton(
                  tooltip: '编辑',
                  icon: Icons.edit_outlined,
                  onPressed: () {
                    final m = selected.single;
                    setState(() {
                      editing = m;
                      reply = null;
                      input.text = m['text'] ?? '';
                      selection.clear();
                    });
                  },
                ),
              TgIconButton(
                tooltip: '复制所选',
                icon: Icons.copy_rounded,
                onPressed: copySelected,
              ),
              if (canRecall)
                TgIconButton(
                  tooltip: '撤回所选',
                  icon: Icons.delete_outline_rounded,
                  onPressed: deleteSelected,
                ),
            ],
          );
    return PreferredSize(
      preferredSize: const Size.fromHeight(76),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TgGlass(
                  child: SizedBox(
                    height: 60,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .2),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                      child: selection.isEmpty ? normal : selecting,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TgGlass(child: actionButtons),
            ],
          ),
        ),
      ),
    );
  }

  ChatEngine get e => widget.engine;
  final input = TextEditingController(), scroll = ScrollController();
  final composerKey = GlobalKey();
  final _shellKey = GlobalKey();
  final _enter = MessageEnterController();
  Json? reply, editing;
  Timer? draftTimer, _highlightTimer;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlighted, _unreadId;
  int _entryReadSeq = 0;
  bool _hadUnread = false,
      _initialPositioned = false,
      _scrolledUp = false,
      _positioning = false;
  final Set<String> _visitedMentions = {};
  bool isMention(Json m) {
    if (m['sender_id'] == e.uid) return false;
    if (objects(m['entities']).any(
      (x) =>
          x['user_id'] == e.uid &&
          ['mention', 'text_mention'].contains(x['type']),
    )) {
      return true;
    }
    final handle = e.me['handle']?.toString() ?? '';
    return handle.isNotEmpty &&
        RegExp('(^|[^A-Za-z0-9_])@${RegExp.escape(handle)}(?![A-Za-z0-9_])')
            .hasMatch(m['text']?.toString() ?? '');
  }

  Future<void> positionOnEntry() async {
    if (!mounted || _initialPositioned) return;
    _initialPositioned = true;
    _positioning = true;
    try {
      if (_hadUnread) {
        while (mounted) {
          final items = e
              .history(widget.cid)
              .where((m) => number(m['conversation_seq']) > 0)
              .toList();
          if (items.isEmpty ||
              number(items.first['conversation_seq']) <= _entryReadSeq + 1) {
            break;
          }
          final before = number(items.first['conversation_seq']);
          await e.loadHistory(widget.cid, before: before);
          if (e
                  .history(widget.cid)
                  .where((m) => number(m['conversation_seq']) > 0)
                  .length ==
              items.length) {
            break;
          }
        }
        final first = e
            .history(widget.cid)
            .where(
              (m) =>
                  number(m['conversation_seq']) > _entryReadSeq &&
                  m['sender_id'] != e.uid,
            )
            .firstOrNull;
        if (first != null && mounted) {
          setState(() => _unreadId = first['id']);
          await jumpToReply(first['id'], highlight: false);
          return;
        }
      }
      bottom(false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _initialPositioned = false;
          loadError = '未读消息暂未加载，可点击重试';
        });
      }
    } finally {
      _positioning = false;
    }
  }

  Future<void> jumpToReply(String id, {bool highlight = true}) async {
    try {
      final target = await e.resolveReply(widget.cid, id);
      if (!mounted || target == null) return;
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      final history = e.history(widget.cid);
      final index = history.indexWhere((m) => m['id'] == id);
      if (index < 0 || !scroll.hasClients) return;
      var context = _messageKeys[id]?.currentContext;
      if (context == null) {
        scroll.jumpTo(scroll.position.maxScrollExtent * index / history.length);
        await WidgetsBinding.instance.endOfFrame;
      }
      // Variable-height lazy bubbles: locate the item, then align precisely.
      for (var i = 0; i < 80 && mounted; i++) {
        context = _messageKeys[id]?.currentContext;
        if (context != null) break;
        final built = <int>[];
        for (var j = 0; j < history.length; j++) {
          if (_messageKeys[history[j]['id']]?.currentContext != null) {
            built.add(j);
          }
        }
        final direction = built.isNotEmpty && index < built.first ? -1 : 1;
        final offset =
            (scroll.offset + direction * scroll.position.viewportDimension * .7)
                .clamp(0.0, scroll.position.maxScrollExtent);
        if (offset == scroll.offset) break;
        scroll.jumpTo(offset);
        await WidgetsBinding.instance.endOfFrame;
      }
      context = _messageKeys[id]?.currentContext;
      if (context == null || !context.mounted) return;
      await Scrollable.ensureVisible(
        context,
        alignment: .4,
        duration: const Duration(milliseconds: 200),
      );
      if (!mounted || !highlight) return;
      _highlightTimer?.cancel();
      setState(() => _highlighted = id);
      _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _highlighted = null);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原消息暂时无法加载，请稍后重试')));
      }
    }
  }

  bool sending = false,
      loading = true,
      reading = false,
      active = true,
      older = false,
      draftDirty = false;
  String? loadError;
  int _lastLength = 0;
  @override
  void initState() {
    super.initState();
    _entryReadSeq = number(e.dialogs[widget.cid]?['last_read_seq']);
    _hadUnread = number(e.dialogs[widget.cid]?['unread_count']) > 0;
    scroll.addListener(() {
      final up = scroll.hasClients && scroll.position.extentAfter > 160;
      if (mounted && up != _scrolledUp) setState(() => _scrolledUp = up);
    });
    WidgetsBinding.instance.addObserver(this);
    input.text = obj(e.dialogs[widget.cid]?['draft'])['text'] ?? '';
    e.addListener(changed);
    unawaited(load());
  }

  Future<void> load() async {
    if (!e.online && e.history(widget.cid).isNotEmpty) {
      setState(() {
        loading = false;
        loadError = null;
      });
      unawaited(positionOnEntry());
      return;
    }
    try {
      await e.loadHistory(widget.cid);
      await e.loadMembers(widget.cid);
      await e.loadPins(widget.cid);
      final draftReply = obj(e.dialogs[widget.cid]?['draft'])['reply_to'];
      reply = e
          .history(widget.cid)
          .where((m) => m['id'] == draftReply)
          .firstOrNull;
      if (mounted) {
        setState(() {
          loading = false;
          loadError = null;
        });
        unawaited(positionOnEntry());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = '历史消息暂未加载，可点击重试';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      markRead();
    } else if (draftDirty) {
      unawaited(flushDraft());
    }
  }

  void changed() {
    if (!mounted) return;
    final count = e.history(widget.cid).length;
    final nearBottom = !scroll.hasClients || scroll.position.extentAfter < 130;
    setState(() {});
    if (count != _lastLength &&
        nearBottom &&
        !older &&
        !loading &&
        !_positioning &&
        _initialPositioned) {
      bottom();
    }
    _lastLength = count;
    if (!loading && nearBottom) markRead();
  }

  void bottom([bool animated = true]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      if (animated && !MediaQuery.disableAnimationsOf(context)) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: slideCurve,
        );
      } else {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
      markRead();
    });
  }

  Future<void> markRead() async {
    if (!mounted ||
        loading ||
        _positioning ||
        reading ||
        !active ||
        ModalRoute.of(context)?.isCurrent != true ||
        (scroll.hasClients && scroll.position.extentAfter > 80)) {
      return;
    }
    final visible = e
        .history(widget.cid)
        .where((m) => number(m['conversation_seq']) > 0)
        .toList();
    if (visible.isEmpty) return;
    reading = true;
    try {
      await e.read(widget.cid, number(visible.last['conversation_seq']));
    } catch (_) {
    } finally {
      reading = false;
    }
  }

  Future<void> flushDraft() async {
    if (!draftDirty || editing != null) return;
    final text = input.text, replyId = reply?['id'] ?? '';
    draftDirty = false;
    final d = e.dialogs[widget.cid];
    if (d != null) {
      d['draft'] = {'text': text, 'entities': [], 'reply_to': replyId};
      await e.persist();
    }
    try {
      await e.draft(widget.cid, text, replyId);
    } catch (_) {
      draftDirty = true;
    }
  }

  void textChanged(String _) {
    if (editing == null) {
      draftDirty = true;
      draftTimer?.cancel();
      draftTimer = Timer(const Duration(milliseconds: 650), flushDraft);
      e.typing(widget.cid, input.text.isNotEmpty);
    }
  }

  Rect? _composerRect() {
    final box = composerKey.currentContext?.findRenderObject() as RenderBox?;
    final shell = _shellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || shell == null || !box.hasSize || !shell.hasSize) {
      return null;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: shell);
    return origin & box.size;
  }

  void _beginEnter(String id, String text) {
    if (skipEnterAnimation(context) || reply != null) return;
    final from = _composerRect();
    if (from == null) return;
    final stamp = TextMessageCell.formatStamp(
      DateTime.now().toUtc().toIso8601String(),
    );
    final to = estimateOutgoingRect(
      viewport: MediaQuery.sizeOf(context),
      viewPadding: MediaQuery.paddingOf(context),
      text: text,
      stamp: stamp,
      composerTop: from.top,
    );
    setState(
      () => _enter.begin(id: id, text: text, stamp: stamp, from: from, to: to),
    );
  }

  Future<void> send() async {
    if (input.text.trim().isEmpty || sending) return;
    final text = input.text.trim(), editingNow = editing;
    setState(() => sending = true);
    await guard(context, () async {
      if (editingNow != null) {
        await e.edit(editingNow, text);
      } else {
        final id = await e.send(widget.cid, text, replyTo: reply?['id'] ?? '');
        if (mounted && editingNow == null) _beginEnter(id, text);
      }
      if (!mounted) return;
      draftTimer?.cancel();
      input.clear();
      draftDirty = false;
      setState(() {
        reply = null;
        editing = null;
      });
      e.typing(widget.cid, false);
      bottom();
      if (editingNow == null) {
        try {
          await e.draft(widget.cid, '', '');
        } catch (_) {}
      }
    });
    if (mounted) setState(() => sending = false);
  }

  Future<void> image() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => sending = true);
    await guard(context, () async {
      final source = await file.readAsBytes();
      if (source.length > 20 * 1024 * 1024) {
        throw const FormatException('原图过大，请选择小于 20 MB 的图片');
      }
      final bytes = await compressImage(source);
      final id = await e.api!.upload(widget.cid, bytes);
      await e.send(
        widget.cid,
        '',
        kind: 'image',
        mediaId: id,
        replyTo: reply?['id'] ?? '',
      );
      if (mounted) setState(() => reply = null);
      bottom();
    });
    if (mounted) setState(() => sending = false);
  }

  Future<void> actions(Json m) async {
    if (m['status'] == 'pending' || m['status'] == 'failed') {
      await guard(context, () => e.retry(m['client_msg_id']));
      return;
    }
    if (m['deleted'] == true) return;
    await guard(context, () => e.loadReactions(m['id']));
    if (!mounted) return;
    await showTgMessageMenu(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in ['👍', '❤', '🔥', '😂', '🎉'])
                    InkWell(
                      onTap: () {
                        Navigator.pop(c);
                        guard(context, () => e.react(m, emoji));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: TextStyle(
                            fontSize: 27,
                            fontFamilyFallback: emojiFallback,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('选择'),
              onTap: () {
                Navigator.pop(c);
                toggleSelected(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('回复'),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  reply = m;
                  editing = null;
                });
                textChanged(input.text);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m['text'] ?? ''));
                Navigator.pop(c);
              },
            ),
            if (m['sender_id'] == e.uid)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    editing = m;
                    reply = null;
                    input.text = m['text'] ?? '';
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('置顶消息'),
              onTap: () {
                Navigator.pop(c);
                guard(context, () => e.pin(m));
              },
            ),
            if (m['sender_id'] == e.uid ||
                ['owner', 'admin'].contains(e.dialogs[widget.cid]?['role']))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('为所有人撤回'),
                onTap: () async {
                  Navigator.pop(c);
                  final yes = await showTgDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('撤回这条消息？'),
                      content: const Text('会为所有成员撤回，但服务器事件或备份可能保留原内容。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('撤回'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && mounted) {
                    await guard(context, () => e.recall(m));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    e.removeListener(changed);
    draftTimer?.cancel();
    if (draftDirty) unawaited(flushDraft());
    input.dispose();
    _highlightTimer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = e.history(widget.cid), pinned = e.pins[widget.cid] ?? [];
    final typing = e.typingUntil[widget.cid]?.isAfter(DateTime.now()) == true;
    final removed = !loading && !e.dialogs.containsKey(widget.cid);
    return PopScope(
      canPop: selection.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selection.isNotEmpty) setState(selection.clear);
      },
      child: Scaffold(
        appBar: header(typing),
        body: Stack(
          key: _shellKey,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: TgWallpaper(
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Column(
                children: [
                  if (pinned.isNotEmpty)
                    InkWell(
                      onTap: () => showTgSheet(
                        context: context,
                        builder: (c) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final p in pinned)
                                ListTile(
                                  leading: const Icon(
                                    Icons.push_pin_outlined,
                                    color: blue,
                                  ),
                                  title: Text(
                                    p['text']?.isNotEmpty == true
                                        ? p['text']
                                        : '[图片]',
                                  ),
                                  trailing: IconButton(
                                    tooltip: '取消置顶',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      Navigator.pop(c);
                                      guard(
                                        context,
                                        () => e.pin(p, remove: true),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      child: Container(
                        color: panel,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.push_pin, size: 18, color: blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '置顶 ${pinned.length} · ${pinned.last['text']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: blue,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (loadError != null)
                    TextButton(onPressed: load, child: Text(loadError!)),
                  if (removed)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('你已离开此会话，无法继续读取或发送消息'),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: loading
                              ? const Center(child: CircularProgressIndicator())
                              : NotificationListener<ScrollNotification>(
                                  onNotification: (_) {
                                    markRead();
                                    return false;
                                  },
                                  child: ListView.builder(
                                    key: const Key('messages'),
                                    controller: scroll,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: 16,
                                    ),
                                    itemCount: history.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return Center(
                                          child: TextButton(
                                            onPressed: history.isEmpty || older
                                                ? null
                                                : () async {
                                                    setState(
                                                      () => older = true,
                                                    );
                                                    final previous = scroll
                                                        .position
                                                        .maxScrollExtent;
                                                    await guard(
                                                      context,
                                                      () => e.loadHistory(
                                                        widget.cid,
                                                        before: number(
                                                          history
                                                              .first['conversation_seq'],
                                                        ),
                                                      ),
                                                    );
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                          if (scroll
                                                              .hasClients) {
                                                            scroll.jumpTo(
                                                              scroll
                                                                      .position
                                                                      .maxScrollExtent -
                                                                  previous +
                                                                  scroll.offset,
                                                            );
                                                          }
                                                        });
                                                    if (mounted) {
                                                      setState(
                                                        () => older = false,
                                                      );
                                                    }
                                                  },
                                            child: Text(
                                              older ? '正在加载…' : '加载更早消息',
                                              style: const TextStyle(
                                                color: muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      final m = history[index - 1];
                                      final newDay =
                                          index == 1 ||
                                          messageDay(history[index - 2]) !=
                                              messageDay(m);
                                      return Column(
                                        key: _messageKeys.putIfAbsent(
                                          m['id'],
                                          () => GlobalKey(),
                                        ),
                                        children: [
                                          if (newDay)
                                            MessageDatePill(message: m),
                                          if (m['id'] == _unreadId)
                                            Container(
                                              key: const Key('unread-divider'),
                                              width: double.infinity,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 9,
                                                  ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              color: const Color(0xff1a2c3a),
                                              child: const Text(
                                                '未读消息',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: blue,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _highlighted == m['id']
                                                  ? blue.withValues(alpha: .18)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: TgSelectableMessage(
                                              selecting: selection.isNotEmpty,
                                              selected: selection.contains(
                                                m['id'],
                                              ),
                                              onToggle: () => toggleSelected(m),
                                              child: Opacity(
                                                opacity: _enter.hides(m['id'])
                                                    ? 0
                                                    : 1,
                                                child: Bubble(
                                                  engine: e,
                                                  onQuoteTap: jumpToReply,
                                                  message: m,
                                                  grouped:
                                                      index < history.length &&
                                                      history[index]['sender_id'] ==
                                                          m['sender_id'] &&
                                                      messageDay(
                                                            history[index],
                                                          ) ==
                                                          messageDay(m),
                                                  onLongPress: () => actions(m),
                                                  onReply: () {
                                                    setState(() {
                                                      reply = m;
                                                      editing = null;
                                                    });
                                                    textChanged(input.text);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: TgSideButtons(
                            visible: _scrolledUp,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (history.any(
                                  (m) =>
                                      isMention(m) &&
                                      number(m['conversation_seq']) >
                                          _entryReadSeq &&
                                      !_visitedMentions.contains(m['id']),
                                )) ...[
                                  FloatingActionButton.small(
                                    heroTag: 'mentions',
                                    tooltip: '跳到未读提及',
                                    onPressed: () {
                                      final target = history.firstWhere(
                                        (m) =>
                                            isMention(m) &&
                                            number(m['conversation_seq']) >
                                                _entryReadSeq &&
                                            !_visitedMentions.contains(m['id']),
                                      );
                                      _visitedMentions.add(target['id']);
                                      unawaited(jumpToReply(target['id']));
                                    },
                                    child: const Text(
                                      '@',
                                      style: TextStyle(fontSize: 23),
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                ],
                                Badge(
                                  isLabelVisible:
                                      number(
                                        e.dialogs[widget.cid]?['unread_count'],
                                      ) >
                                      0,
                                  label: Text(
                                    '${number(e.dialogs[widget.cid]?['unread_count'])}',
                                  ),
                                  child: FloatingActionButton.small(
                                    heroTag: 'bottom',
                                    tooltip: '回到最新消息',
                                    onPressed: bottom,
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reply != null || editing != null)
                    Container(
                      color: panel,
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, color: blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${editing != null ? '编辑消息' : '回复'} · ${replyPreview(editing ?? reply)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: blue),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (editing != null) input.clear();
                                editing = null;
                                reply = null;
                              });
                              textChanged(input.text);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  if (selection.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: [
                          if (selection.length == 1)
                            Expanded(
                              child: TgGlass(
                                child: TextButton.icon(
                                  onPressed: replySelected,
                                  icon: const Icon(Icons.reply_rounded),
                                  label: const Text('回复'),
                                ),
                              ),
                            ),
                          if (selection.length == 1) const SizedBox(width: 10),
                          Expanded(
                            child: TgGlass(
                              child: TextButton.icon(
                                onPressed: copySelected,
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('复制'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    TgGlass(
                      margin: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(3, 5, 7, 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TgIconButton(
                              tooltip: '表情',
                              icon: Icons.emoji_emotions_outlined,
                              onPressed: removed ? null : emojiPanel,
                              color: muted,
                              size: 40,
                            ),
                            Expanded(
                              child: KeyedSubtree(
                                key: const Key('composer'),
                                child: TextField(
                                  key: composerKey,
                                  controller: input,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 4000,
                                  enabled: !removed,
                                  onChanged: textChanged,
                                  decoration: const InputDecoration(
                                    hintText: '消息',
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 13,
                                      horizontal: 5,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => send(),
                                ),
                              ),
                            ),
                            TgIconButton(
                              tooltip: '添加图片',
                              icon: Icons.attach_file_rounded,
                              onPressed: sending || removed || !e.online
                                  ? null
                                  : image,
                              color: muted,
                              size: 38,
                            ),
                            const SizedBox(width: 4),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: input,
                              builder: (context, value, _) => TgComposerAction(
                                key: const Key('send'),
                                sending: sending,
                                hasText: value.text.trim().isNotEmpty,
                                enabled: !sending && !removed,
                                onSend: send,
                                onCamera: () => input.text.trim().isNotEmpty
                                    ? send()
                                    : image(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_enter.active && _enter.from != null && _enter.to != null)
              MessageEnterLayer(
                key: ValueKey(_enter.id),
                text: _enter.text,
                stamp: _enter.stamp,
                from: _enter.from!,
                to: _enter.to!,
                onDone: () {
                  if (mounted) setState(_enter.complete);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> showInfo() async {
    await Navigator.push(
      context,
      TgPageRoute(
        duration: const Duration(milliseconds: 180),
        curve: Curves.decelerate,
        page: ChatInfoPage(
          engine: e,
          cid: widget.cid,
          title: widget.title,
          members: const [],
          avatarBuilder: (radius) => Avatar(widget.title, radius: radius),
          onSearch: localSearch,
        ),
      ),
    );
  }
}

Future<Uint8List> compressImage(Uint8List source) async {
  // image package decodes on caller isolate below via compute; no server transcoding.
  return await computeCompress(source);
}

Future<Uint8List> computeCompress(Uint8List source) =>
    compute(_imageInWorker, source);
Uint8List _imageInWorker(Uint8List source) {
  final decoder = img.findDecoderForData(source);
  final info = decoder?.startDecode(source);
  if (info == null || info.width * info.height > 40000000) {
    throw const FormatException('图片格式不支持或像素过大');
  }
  var decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('无法读取图片');
  decoded = img.bakeOrientation(decoded);
  if (decoded.width > 1600 || decoded.height > 1600) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 1600 : null,
      height: decoded.height > decoded.width ? 1600 : null,
    );
  }
  decoded.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 82));
}

String messageDay(Json message) {
  final date = DateTime.tryParse(message['created_at']?.toString() ?? '')
      ?.toUtc()
      .add(const Duration(hours: 8));
  return date == null ? '' : '${date.year}-${date.month}-${date.day}';
}

class MessageDatePill extends StatelessWidget {
  final Json message;
  const MessageDatePill({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final day = messageDay(message).split('-');
    if (day.length != 3) return const SizedBox.shrink();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xcc243443),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${day[1]}月${day[2]}日',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ),
    );
  }
}

class Bubble extends StatefulWidget {
  final ChatEngine engine;
  final Json message;
  final VoidCallback onLongPress, onReply;
  final ValueChanged<String>? onQuoteTap;
  final bool grouped;
  const Bubble({
    super.key,
    required this.engine,
    required this.message,
    required this.onLongPress,
    required this.onReply,
    this.onQuoteTap,
    this.grouped = false,
  });
  @override
  State<Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<Bubble> {
  bool reveal = false;
  double dx = 0;
  Future<Uint8List>? image;
  String? mediaId;
  @override
  void didUpdateWidget(covariant Bubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message['deleted'] == true) {
      image = null;
      mediaId = null;
    }
  }

  Widget nativeTextCell(
    Json m,
    ChatEngine e,
    bool mine,
    bool pending,
    bool failed,
    String stamp,
  ) {
    return TextMessageCell(
      text: m['text'] ?? '',
      stamp: stamp,
      mine: mine,
      grouped: widget.grouped,
      pending: pending,
      failed: failed,
      read:
          mine &&
          e.dialogs[m['conversation_id']]?['kind'] == 'direct' &&
          e.isRead(m),
      edited: m['edited_at']?.toString().isNotEmpty == true,
      groupReads:
          mine &&
              !pending &&
              e.dialogs[m['conversation_id']]?['kind'] == 'group' &&
              e.receipts
          ? e.readPositions[m['conversation_id']]?.entries
                .where(
                  (r) =>
                      r.key != e.uid &&
                      r.value != null &&
                      r.value! >= number(m['conversation_seq']),
                )
                .length
          : null,
      textWidget: EntityText(
        text: m['text'] ?? '',
        entities: objects(m['entities']),
        revealed: reveal,
        onReveal: () => setState(() => reveal = true),
      ),
    );
  }

  Widget _interactive({required Widget child}) {
    final deleted = widget.message['deleted'] == true;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (d) {
        if (!deleted) setState(() => dx = (dx + d.delta.dx).clamp(0, 70));
      },
      onHorizontalDragEnd: (_) {
        if (dx > 48) {
          HapticFeedback.selectionClick();
          widget.onReply();
        }
        setState(() => dx = 0);
      },
      child: Transform.translate(offset: Offset(dx, 0), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message,
        e = widget.engine,
        mine = m['sender_id'] == e.uid,
        deleted = m['deleted'] == true;
    final pending = m['status'] == 'pending', failed = m['status'] == 'failed';
    final rawReply = m['reply_to'];
    final replyId = rawReply is String ? rawReply.trim() : '';
    final hasReply = replyId.isNotEmpty && replyId != '0' && replyId != 'null';
    final parent = hasReply
        ? e.messages.values.where((p) => p['id'] == replyId).firstOrNull
        : null;
    final reactions = e.reactions[m['id']] ?? [];
    final date = DateTime.tryParse(m['created_at'] ?? '');
    final china = date?.toUtc().add(const Duration(hours: 8));
    final stamp = china == null
        ? ''
        : '${china.hour.toString().padLeft(2, '0')}:${china.minute.toString().padLeft(2, '0')}';
    final id = m['media_id'] as String?;
    if (!deleted &&
        m['kind'] == 'image' &&
        id != null &&
        id.isNotEmpty &&
        id != mediaId) {
      mediaId = id;
      image = e.api!.media(id);
    }
    if (usesNativeTextCell(m) && reactions.isEmpty) {
      return _interactive(
        child: nativeTextCell(m, e, mine, pending, failed, stamp),
      );
    }
    return TweenAnimationBuilder<double>(
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 250,
      ),
      curve: sendCurve,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(
            dx + (mine && pending ? 20 * (1 - value) : 0),
            (mine && pending ? 92 : 18) * (1 - value),
          ),
          child: child,
        ),
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: widget.onLongPress,
          onHorizontalDragUpdate: (d) {
            if (!deleted) setState(() => dx = (dx + d.delta.dx).clamp(0, 70));
          },
          onHorizontalDragEnd: (_) {
            if (dx > 48) {
              HapticFeedback.selectionClick();
              widget.onReply();
            }
            setState(() => dx = 0);
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: slideCurve,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 650) * .80,
              ),
              margin: EdgeInsets.only(top: 2, bottom: widget.grouped ? 0 : 4),
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
              decoration: ShapeDecoration(
                color: mine ? const Color(0xff24445e) : panel,
                shape: TgBubbleShape(mine: mine, grouped: widget.grouped),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine &&
                      e.dialogs[m['conversation_id']]?['kind'] == 'group')
                    FutureBuilder<Json>(
                      future: e.user(m['sender_id']),
                      builder: (_, snapshot) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          snapshot.data?['display_name'] ?? '成员',
                          style: const TextStyle(fontSize: 12, color: blue),
                        ),
                      ),
                    ),
                  if (!deleted && hasReply)
                    ReplyQuote(
                      engine: e,
                      conversationId: m['conversation_id'],
                      messageId: replyId,
                      parent: parent,
                      before: number(m['conversation_seq']),
                      onTap: () => widget.onQuoteTap?.call(replyId),
                    ),
                  if (!deleted && image != null)
                    FutureBuilder<Uint8List>(
                      future: image,
                      builder: (_, s) => s.hasData
                          ? GestureDetector(
                              onTap: () => openImageViewer(
                                context,
                                bytes: s.data!,
                                tag: 'media-${m['id']}',
                                sender:
                                    e.users[m['sender_id']]?['display_name'] ??
                                    (mine ? '你' : '成员'),
                                time: '$stamp · 中国标准时间 UTC+8',
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Hero(
                                  tag: 'media-${m['id']}',
                                  createRectTween: (begin, end) =>
                                      ImageRectTween(begin: begin, end: end),
                                  child: Image.memory(
                                    s.data!,
                                    width: 240,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(25),
                              child: s.hasError
                                  ? TextButton(
                                      onPressed: () => setState(
                                        () => image = e.api!.media(mediaId!),
                                      ),
                                      child: const Text('图片加载失败，重试'),
                                    )
                                  : const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                            ),
                    ),
                  if (deleted)
                    const Text(
                      '消息已撤回',
                      style: TextStyle(
                        color: muted,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (m['text']?.toString().isNotEmpty == true)
                    EntityText(
                      text: m['text'],
                      entities: objects(m['entities']),
                      revealed: reveal,
                      onReveal: () => setState(() => reveal = true),
                    ),
                  if (!deleted && m['link_preview'] != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.only(left: 8),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: blue, width: 2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            obj(m['link_preview'])['title'] ?? '',
                            style: const TextStyle(color: blue),
                          ),
                          Text(
                            obj(m['link_preview'])['description'] ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  if (!deleted && reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 5,
                        children: [
                          for (final emoji
                              in reactions.map((r) => r['emoji']).toSet())
                            InkWell(
                              onTap: () =>
                                  guard(context, () => e.react(m, emoji)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: bg.withValues(alpha: .4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$emoji ${reactions.where((r) => r['emoji'] == emoji).length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamilyFallback: emojiFallback,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (m['edited_at']?.toString().isNotEmpty == true &&
                          !deleted)
                        const Text(
                          '已编辑 · ',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      Text(
                        '$stamp CST',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          failed
                              ? Icons.error_outline
                              : pending
                              ? Icons.schedule
                              : e.dialogs[m['conversation_id']]?['kind'] ==
                                        'direct' &&
                                    e.isRead(m)
                              ? Icons.done_all
                              : Icons.check,
                          color: failed ? Colors.orangeAccent : blue,
                          size: 15,
                        ),
                      ],
                      if (mine &&
                          !pending &&
                          e.dialogs[m['conversation_id']]?['kind'] == 'group' &&
                          e.receipts)
                        Text(
                          ' ${e.readPositions[m['conversation_id']]?.entries.where((r) => r.key != e.uid && r.value != null && r.value! >= number(m['conversation_seq'])).length ?? 0}人已读',
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                    ],
                  ),
                  if (failed)
                    TextButton(
                      onPressed: widget.onLongPress,
                      child: const Text(
                        '发送失败 · 点此重试',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (!deleted)
                    for (final row
                        in (obj(m['reply_markup'])['inline_keyboard']
                                as List? ??
                            []))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final raw in row as List)
                            Flexible(
                              child: TextButton(
                                onPressed: () {
                                  final b = obj(raw);
                                  if (b['url'] != null) {
                                    openLink(context, b['url']);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Bot 按钮回调将在第二期开放'),
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  obj(raw)['text'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// UTF-16 offsets match Dart String indexes. Segment boundaries preserve nesting:
/// styles accumulate; link spans are only launched after explicit user tap.
class EntityText extends StatefulWidget {
  final String text;
  final List<Json> entities;
  final bool revealed;
  final VoidCallback onReveal;
  final InlineSpan? suffix;
  const EntityText({
    super.key,
    required this.text,
    required this.entities,
    required this.revealed,
    required this.onReveal,
    this.suffix,
  });
  @override
  State<EntityText> createState() => _EntityTextState();
}

class _EntityTextState extends State<EntityText> {
  final List<TapGestureRecognizer> _recognizers = [];
  void clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }

  bool boundary(int n) =>
      n == 0 ||
      n == widget.text.length ||
      !(widget.text.codeUnitAt(n) >= 0xdc00 &&
          widget.text.codeUnitAt(n) <= 0xdfff);
  @override
  Widget build(BuildContext context) {
    clear();
    final valid = widget.entities.where((e) {
      final start = number(e['offset']), end = start + number(e['length']);
      return start >= 0 &&
          end <= widget.text.length &&
          start < end &&
          boundary(start) &&
          boundary(end);
    }).toList();
    final points = <int>{0, widget.text.length};
    for (final e in valid) {
      points.add(number(e['offset']));
      points.add(number(e['offset']) + number(e['length']));
    }
    final breaks = points.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i + 1 < breaks.length; i++) {
      final start = breaks[i], end = breaks[i + 1];
      var style = TextStyle(
        fontSize: 15,
        height: 1.45,
        fontFamily: chatFont,
        fontFamilyFallback: emojiFallback,
      );
      String? url;
      bool spoiler = false;
      final decorations = <TextDecoration>[];
      for (final e in valid.where(
        (e) =>
            number(e['offset']) <= start &&
            number(e['offset']) + number(e['length']) >= end,
      )) {
        switch (e['type']) {
          case 'bold':
            style = style.copyWith(fontWeight: FontWeight.bold);
          case 'italic':
            style = style.copyWith(fontStyle: FontStyle.italic);
          case 'underline':
            decorations.add(TextDecoration.underline);
          case 'strikethrough':
            decorations.add(TextDecoration.lineThrough);
          case 'code':
          case 'pre':
            style = style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.black26,
            );
          case 'blockquote':
            style = style.copyWith(color: blue, fontStyle: FontStyle.italic);
          case 'text_link':
            url = e['url'];
          case 'url':
            url = widget.text.substring(
              number(e['offset']),
              number(e['offset']) + number(e['length']),
            );
          case 'mention':
          case 'hashtag':
            style = style.copyWith(color: blue);
          case 'spoiler':
            spoiler = !widget.revealed;
        }
      }
      TapGestureRecognizer? tap;
      if (spoiler) {
        style = style.copyWith(
          color: Colors.transparent,
          backgroundColor: muted,
        );
        tap = TapGestureRecognizer()..onTap = widget.onReveal;
      } else if (url != null) {
        style = style.copyWith(
          color: blue,
          decoration: TextDecoration.underline,
        );
        final target = url;
        tap = TapGestureRecognizer()..onTap = () => openLink(context, target);
      }
      if (decorations.isNotEmpty) {
        style = style.copyWith(decoration: TextDecoration.combine(decorations));
      }
      if (tap != null) _recognizers.add(tap);
      spans.add(
        TextSpan(
          text: widget.text.substring(start, end),
          style: style,
          recognizer: tap,
        ),
      );
    }
    if (widget.suffix != null) spans.add(widget.suffix!);
    return RichText(text: TextSpan(children: spans));
  }
}

class NewChatPage extends StatefulWidget {
  final ChatEngine engine;
  const NewChatPage({super.key, required this.engine});
  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final query = TextEditingController(), title = TextEditingController();
  final Set<String> selected = {};
  List<Json> results = [];
  bool group = false, busy = false;
  Timer? debounce;
  int generation = 0;
  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    title.dispose();
    super.dispose();
  }

  void search(String q) {
    final g = ++generation;
    debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => results = []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 350), () async {
      await guard(context, () async {
        final data = await widget.engine.api!.call(
          'GET',
          '/users?q=${Uri.encodeQueryComponent(q.trim())}',
        );
        if (mounted && g == generation) {
          setState(
            () =>
                results = objects(data['users'])
                    .where((u) => u['id'] != widget.engine.uid)
                    .toList(),
          );
        }
      });
    });
  }

  Future<void> create() async {
    if (selected.isEmpty || (group && title.text.trim().isEmpty)) return;
    setState(() => busy = true);
    await guard(context, () async {
      final result = obj(
        await widget.engine.api!.call('POST', '/conversations', {
          'kind': group ? 'group' : 'direct',
          'title': group ? title.text.trim() : '',
          'member_ids': selected.toList(),
        }),
      );
      await widget.engine.refreshDialogs();
      if (!mounted) return;
      final d = widget.engine.dialogs[result['id']] ?? result;
      final name = await widget.engine.title(d);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          chatRoute(
            ChatPage(engine: widget.engine, cid: result['id'], title: name),
          ),
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(group ? '新建群聊' : '新建私聊')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('多人群聊'),
            value: group,
            onChanged: (v) => setState(() {
              group = v;
              selected.clear();
            }),
          ),
          if (group)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '群名称'),
              ),
            ),
          TextField(
            key: const Key('user-search'),
            controller: query,
            onChanged: search,
            decoration: const InputDecoration(
              hintText: '搜索用户名（至少 2 个字符）',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final u in results)
                  CheckboxListTile(
                    value: selected.contains(u['id']),
                    secondary: Avatar(u['display_name'] ?? u['handle']),
                    title: Text(u['display_name'] ?? u['handle']),
                    subtitle: Text('@${u['handle']}'),
                    onChanged: (v) => setState(() {
                      if (!group) selected.clear();
                      if (v == true) {
                        selected.add(u['id']);
                      } else {
                        selected.remove(u['id']);
                      }
                    }),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selected.isEmpty || busy ? null : create,
              child: Text(
                busy
                    ? '创建中…'
                    : '开始聊天 ${group ? '(${selected.length + 1}人)' : ''}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfilePage extends StatefulWidget {
  final ChatEngine engine;
  const ProfilePage({super.key, required this.engine});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final name = TextEditingController();
  PushPlan? plan;
  ChatEngine get e => widget.engine;
  @override
  void initState() {
    super.initState();
    name.text = e.me['display_name'] ?? '';
    PushPlan.detect().then((p) {
      if (mounted) setState(() => plan = p);
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: e,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('个人资料与设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Avatar(e.me['display_name'] ?? '我', radius: 34)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '@${e.me['handle'] ?? ''}',
              style: const TextStyle(color: muted),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '昵称'),
          ),
          TextButton(
            onPressed: () => guard(context, () async {
              await e.api!.call('PATCH', '/me', {
                'display_name': name.text.trim(),
                'avatar_media_id': e.me['avatar_media_id'] ?? '',
              });
              e.me = obj(await e.api!.call('GET', '/me'));
              await e.persist();
              if (mounted) setState(() {});
            }),
            child: const Text('保存昵称'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('公开已读回执'),
            subtitle: Text(
              e.privacy['global_read_receipts_enabled'] == false
                  ? '管理员已全局关闭回执'
                  : '互惠设置：关闭后也看不到他人的已读',
            ),
            value: e.privacy['read_receipts_enabled'] == true,
            onChanged: (v) => guard(context, () async {
              await e.api!.call('PUT', '/me/privacy', {
                'read_receipts_enabled': v,
              });
              e.privacy = obj(await e.api!.call('GET', '/me/privacy'));
              e.readPositions.clear();
              await e.refreshDialogs();
              if (mounted) setState(() {});
            }),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('连接诊断'),
            subtitle: Text(
              '${e.connectionStage}${e.lastConnectionFailure.isEmpty ? '' : '\n最近失败：${e.lastConnectionFailure}'}',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('推送通道：未启用'),
            subtitle: Text(
              'Mi Push / FCM 为适配接口，未接入 SDK、凭据和通知权限。无后台常驻服务，不承诺锁屏送达。',
            ),
          ),
          if (plan != null)
            Text(
              plan!.explanation,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          const SizedBox(height: 18),
          const Text('安全边界', style: TextStyle(color: blue)),
          const SizedBox(height: 8),
          const Text(
            '这是一款独立的云端聊天应用。\n没有端到端加密；服务器可访问消息内容。\n登录令牌保存在 Android 加密存储；消息缓存位于应用私有 SQLite（未额外加密）。\n所有时间显示为中国标准时间 CST（UTC+8）。',
            style: TextStyle(color: muted, height: 1.7, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Text(
            e.session?['server'] ?? '',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () async {
              final ok = await showTgDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('退出当前账号？'),
                  content: const Text('将撤销本设备登录并清理本地缓存，未发送的消息也会清除。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('退出'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await guard(context, () async {
                  await e.logout();
                  if (context.mounted) Navigator.pop(context);
                });
              }
            },
            child: const Text('退出登录'),
          ),
          if (e.suspended && e.error.contains('登录'))
            TextButton(
              onPressed: () => guard(context, () async {
                await e.logout(localOnly: true);
                if (context.mounted) Navigator.pop(context);
              }),
              child: const Text('登录失效：仅清除本地会话'),
            ),
        ],
      ),
    ),
  );
}
