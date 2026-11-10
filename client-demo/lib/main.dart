import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

const bg = Color(0xff0e1621),
    panel = Color(0xff17212b),
    blue = Color(0xff5dade6),
    muted = Color(0xff7d91a5);
const slideCurve = Cubic(.33, .52, .25, .99);
const sendCurve = Cubic(.1992, .0106, .2792, .9103);
void main() => runApp(const ChatDemo());

class ChatDemo extends StatelessWidget {
  const ChatDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '轻聊 · 交互实验室',
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
      colorScheme: const ColorScheme.dark(
        primary: blue,
        secondary: blue,
        secondaryContainer: Color(0xff24394c),
        onSecondaryContainer: blue,
        surface: panel,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: 'ChatSans',
        bodyColor: const Color(0xffeef4fa),
        displayColor: const Color(0xffeef4fa),
      ),
    ),
    home: LayoutBuilder(
      builder: (context, constraints) =>
          DemoHome(wide: constraints.maxWidth >= 780),
    ),
  );
}

class Contact {
  final String name, text, time, initials;
  final Color color;
  final int unread;
  const Contact(
    this.name,
    this.text,
    this.time,
    this.initials,
    this.color, [
    this.unread = 0,
  ]);
}

const contacts = [
  Contact('林间设计室', '阿澈：好设计，是让每一次操作都自然。', '21:46', '林', Color(0xff548bac), 3),
  Contact('小夏', '今晚的月亮，像一枚会发光的贴纸。', '21:38', '夏', Color(0xffab806c), 2),
  Contact('产品漫游', '你：我们先把手感打磨好。', '20:52', '漫', Color(0xff7d84b1)),
  Contact('阿澈', '发来一个动态贴纸', '19:24', '澈', Color(0xff688e80)),
  Contact('收藏夹', '把灵感留在这里。', '昨天', '☆', Color(0xff538ab1)),
];

class Msg {
  final String text;
  final bool mine;
  final String? sticker;
  final int id;
  String? reply;
  String? reaction;
  Msg(this.id, this.text, {this.mine = false, this.sticker, this.reply});
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key, required this.wide});
  final bool wide;
  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> with TickerProviderStateMixin {
  Contact? contact;
  bool reduced = false, stickerOpen = false, slow = false;
  Msg? reply;
  final input = TextEditingController(), scroll = ScrollController();
  final stageKey = GlobalKey(), composerKey = GlobalKey();
  late final AnimationController route = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final AnimationController dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  late final AnimationController burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  List<Msg> messages = [];
  int serial = 10;
  double backDx = 0;
  bool edge = false;
  Offset? edgeStart;
  Offset burstAt = Offset.zero;
  String burstEmoji = '❤';
  Msg? menuMsg;
  Offset menuAt = Offset.zero;
  String query = '';
  String? flyingText;
  Rect? flyFrom, flyTo;
  final flyKey = GlobalKey();
  late final AnimationController flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  final Map<String, List<Msg>> histories = {};
  int duration(int ms) => reduced
      ? 1
      : slow
      ? ms * 3
      : ms;
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    route.dispose();
    dots.dispose();
    burst.dispose();
    flight.dispose();
    super.dispose();
  }

  void open(Contact c) {
    if (contact != null) histories[contact!.name] = messages;
    setState(() {
      contact = c;
      backDx = 0;
      reply = null;
      stickerOpen = false;
      menuMsg = null;
      messages = histories.putIfAbsent(
        c.name,
        () => [
          Msg(1, '终于有空一起聊聊新想法了。'),
          Msg(2, '不堆功能，先把每一次点击和滑动做好。', mine: true),
          Msg(3, '对。手指到哪里，界面就跟到哪里。'),
          Msg(4, '试试滑动这条消息回复我，或者长按添加一个回应。'),
          Msg(5, '', sticker: 'sun'),
          Msg(6, '细节会被感受到 ✨', mine: true),
        ],
      );
    });
    route.duration = Duration(milliseconds: duration(240));
    route.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => bottom(false));
  }

  void back() async {
    menuMsg = null;
    route.duration = Duration(milliseconds: duration(180));
    await route.reverse();
    if (mounted) {
      setState(() {
        if (contact != null) histories[contact!.name] = messages;
        contact = null;
        backDx = 0;
        stickerOpen = false;
      });
    }
  }

  void bottom([bool animated = true]) {
    if (scroll.hasClients) {
      if (animated && !reduced) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: Duration(milliseconds: duration(240)),
          curve: Curves.easeOut,
        );
      } else {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    }
  }

  void send({String? sticker}) async {
    final text = input.text.trim();
    if (sticker == null && text.isEmpty) return;
    if (flight.isAnimating) {
      flight.stop();
      setState(() => flyingText = null);
    }
    final composer =
        composerKey.currentContext?.findRenderObject() as RenderBox?;
    final stage = stageKey.currentContext?.findRenderObject() as RenderBox?;
    final from = composer != null && stage != null
        ? composer.localToGlobal(const Offset(48, 8), ancestor: stage)
        : Offset.zero;
    setState(() {
      messages.add(
        Msg(++serial, text, mine: true, sticker: sticker, reply: reply?.text),
      );
      input.clear();
      reply = null;
      stickerOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bottom(false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = flyKey.currentContext?.findRenderObject() as RenderBox?;
        if (target == null || stage == null || reduced) return;
        final dest = target.localToGlobal(Offset.zero, ancestor: stage);
        setState(() {
          flyFrom = Rect.fromLTWH(
            from.dx,
            from.dy,
            math.min(target.size.width, 290),
            math.min(target.size.height, 52),
          );
          flyTo = dest & target.size;
          flyingText = sticker == null ? text : '✦';
        });
        flight.duration = Duration(milliseconds: duration(250));
        flight.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => flyingText = null);
        });
      });
    });
  }

  void react(String emoji) {
    if (menuMsg == null) return;
    setState(() {
      menuMsg!.reaction = emoji;
      burstAt = menuAt;
      burstEmoji = emoji;
      menuMsg = null;
    });
    if (!reduced) {
      burst.duration = Duration(milliseconds: duration(600));
      burst.forward(from: 0);
    }
  }

  Widget avatar(Contact c, [double size = 50]) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c.color,
      borderRadius: BorderRadius.circular(size / 2),
    ),
    alignment: Alignment.center,
    child: Text(
      c.initials,
      style: TextStyle(
        fontSize: size * .4,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
  Widget icon(IconData i, String tip, VoidCallback action) => IconButton(
    tooltip: tip,
    onPressed: action,
    icon: Icon(i, size: 22, color: muted),
  );
  @override
  Widget build(BuildContext context) {
    final wide = widget.wide;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (menuMsg != null) {
                setState(() => menuMsg = null);
              } else if (stickerOpen) {
                setState(() => stickerOpen = false);
              } else if (contact != null) {
                back();
              }
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 22, 32, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bubble_chart_rounded,
                          color: blue,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '轻聊',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'MOTION STUDY / 01',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: muted,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '本地交互演示 · 消息不联网',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(wide ? 18 : 0),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xff293746)),
                        ),
                        child: Row(
                          children: [
                            if (wide) SizedBox(width: 326, child: chatList()),
                            Expanded(
                              child: Stack(
                                key: stageKey,
                                children: [
                                  Positioned.fill(
                                    child: wide ? welcome() : chatList(),
                                  ),
                                  if (contact != null)
                                    AnimatedBuilder(
                                      animation: route,
                                      builder: (context, child) =>
                                          Transform.translate(
                                            offset: Offset(
                                              (1 -
                                                          slideCurve.transform(
                                                            route.value,
                                                          )) *
                                                      MediaQuery.sizeOf(context)
                                                          .width *
                                                      .55 +
                                                  backDx,
                                              0,
                                            ),
                                            child: child,
                                          ),
                                      child: Listener(
                                        onPointerDown: (e) {
                                          edge = e.localPosition.dx < 28;
                                          edgeStart = e.position;
                                        },
                                        onPointerMove: (e) {
                                          if (edge && edgeStart != null) {
                                            final d = e.position - edgeStart!;
                                            if (d.dx > 0 &&
                                                d.dx > d.dy.abs() * 1.5) {
                                              setState(() => backDx = d.dx);
                                            }
                                          }
                                        },
                                        onPointerUp: (e) {
                                          if (edge && backDx > 90) {
                                            back();
                                          } else {
                                            setState(() => backDx = 0);
                                          }
                                          edge = false;
                                          edgeStart = null;
                                        },
                                        onPointerCancel: (_) {
                                          setState(() => backDx = 0);
                                          edge = false;
                                        },
                                        child: chat(),
                                      ),
                                    ),
                                  if (flyingText != null &&
                                      flyFrom != null &&
                                      flyTo != null)
                                    AnimatedBuilder(
                                      animation: flight,
                                      builder: (context, _) {
                                        final rect = Rect.lerp(
                                          flyFrom,
                                          flyTo,
                                          sendCurve.transform(flight.value),
                                        )!;
                                        return Positioned(
                                          left: rect.left,
                                          top: rect.top,
                                          width: rect.width,
                                          height: rect.height,
                                          child: IgnorePointer(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xff2b5278),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Text(
                                                flyingText!,
                                                overflow: TextOverflow.clip,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (menuMsg != null)
                                    Positioned.fill(child: contextMenu()),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: AnimatedBuilder(
                                        animation: burst,
                                        builder: (context, _) => CustomPaint(
                                          painter: BurstPainter(
                                            burst.value,
                                            burstAt,
                                            burstEmoji,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 14, 36, 20),
                    child: Row(
                      children: [
                        const Text(
                          '拖动回复  /  长按回应  /  左缘拖动返回  /  Enter 发送',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        const Spacer(),
                        const Text(
                          '慢放',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        Switch(
                          value: slow,
                          onChanged: (v) => setState(() => slow = v),
                        ),
                        const Text(
                          '减少动效',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        Switch(
                          value: reduced,
                          onChanged: (v) {
                            setState(() => reduced = v);
                            if (v) {
                              dots.stop();
                            } else {
                              dots.repeat();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget chatList() => ColoredBox(
    color: panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Text(
                '消息',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              icon(
                Icons.tune_rounded,
                '演示设置',
                () => showModalBottomSheet(
                  context: context,
                  backgroundColor: panel,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '这是交互原型，不是真实聊天服务。',
                          style: TextStyle(fontSize: 17),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() => reduced = !reduced);
                                Navigator.pop(context);
                              },
                              child: Text(reduced ? '启用动效' : '减少动态效果'),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => slow = !slow);
                                Navigator.pop(context);
                              },
                              child: Text(slow ? '正常速度' : '3 倍慢放'),
                            ),
                          ],
                        ),
                        const Text(
                          '三款原创笑脸贴纸：CC0 1.0。\n不连接账号，不保存消息，不录音。',
                          style: TextStyle(color: muted, height: 1.8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: TextField(
            onChanged: (s) => setState(() => query = s),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索会话',
              prefixIcon: const Icon(Icons.search, color: muted, size: 21),
              filled: true,
              fillColor: bg,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            children: [
              const Text(
                '全部消息',
                style: TextStyle(
                  color: blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '5',
                  style: TextStyle(color: blue, fontSize: 11),
                ),
              ),
              const SizedBox(width: 22),
              const Text('未读', style: TextStyle(color: muted, fontSize: 13)),
              const SizedBox(width: 22),
              const Text('群组', style: TextStyle(color: muted, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: contacts
                .where((c) => c.name.contains(query) || c.text.contains(query))
                .map(contactTile)
                .toList(),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xff263440))),
          ),
          child: const Row(
            children: [
              Icon(Icons.science_outlined, color: muted, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '虚构联系人 · 仅用于手感体验',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget contactTile(Contact c) => Material(
    color: contact == c ? const Color(0xff24394c) : Colors.transparent,
    child: InkWell(
      key: ValueKey('contact-${c.name}'),
      onTap: () => open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            avatar(c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        c.time,
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      if (c.unread > 0)
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: blue,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${c.unread}',
                            style: const TextStyle(
                              color: bg,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget typingIndicator() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedBuilder(
            animation: dots,
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Transform.translate(
                  offset: Offset(
                    0,
                    reduced
                        ? 0
                        : -3 *
                              math
                                  .sin((dots.value - i * .16) * math.pi * 2)
                                  .clamp(0, 1),
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('模拟输入中', style: TextStyle(color: muted, fontSize: 10)),
      ],
    ),
  );
  Widget welcome() => ColoredBox(
    color: bg,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: .09),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_outlined, color: blue, size: 40),
          ),
          const SizedBox(height: 28),
          const Text(
            '让对话，自然发生。',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '不止是界面。更是每一次触碰后的回应。',
            style: TextStyle(fontSize: 14, color: muted),
          ),
          const SizedBox(height: 34),
          FilledButton.icon(
            onPressed: () => open(contacts.first),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Text('进入交互演示'),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '本地运行 / 无网络消息 / 无真实在线状态',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    ),
  );
  Widget chat() => ColoredBox(
    color: bg,
    child: Column(
      children: [
        Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: panel,
            border: Border(bottom: BorderSide(color: Color(0xff263440))),
          ),
          child: Row(
            children: [
              icon(Icons.arrow_back_rounded, '返回会话列表', back),
              avatar(contact!, 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact!.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '交互演示 · 正在输入为模拟效果',
                      style: TextStyle(fontSize: 11, color: blue),
                    ),
                  ],
                ),
              ),
              icon(
                Icons.info_outline,
                '演示说明',
                () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('联系人和消息均为虚构。所有操作仅在当前页面内生效。')),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: WallpaperPainter())),
              ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '今天 · 本地演示',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...messages.map(message),
                  typingIndicator(),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 14,
                child: IconButton.filledTonal(
                  tooltip: '回到底部',
                  onPressed: bottom,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (reply != null)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 8),
            color: panel,
            child: Row(
              children: [
                Container(width: 3, height: 32, color: blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '回复消息',
                        style: TextStyle(color: blue, fontSize: 11),
                      ),
                      Text(
                        reply!.text.isEmpty ? '动态贴纸' : reply!.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                icon(Icons.close, '取消回复', () => setState(() => reply = null)),
              ],
            ),
          ),
        Container(
          key: composerKey,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          color: panel,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              icon(
                stickerOpen ? Icons.keyboard : Icons.emoji_emotions_outlined,
                '动态贴纸',
                () {
                  setState(() => stickerOpen = !stickerOpen);
                  WidgetsBinding.instance.addPostFrameCallback((_) => bottom());
                },
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () =>
                        send(),
                  },
                  child: TextField(
                    key: const ValueKey('message-input'),
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: '发送一条消息，感受它的轨迹…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: FilledButton(
                  key: const ValueKey('send-button'),
                  onPressed: send,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.send_rounded, size: 21),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: duration(240)),
          curve: slideCurve,
          alignment: Alignment.topCenter,
          child: stickerOpen
              ? Container(
                  height: 208,
                  width: double.infinity,
                  color: panel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(22, 12, 20, 0),
                        child: Text(
                          '原创动态贴纸  /  CC0 1.0',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: ['sun', 'moon', 'mint']
                              .map(
                                (s) => Tooltip(
                                  message: '发送 $s 笑脸',
                                  child: InkWell(
                                    onTap: () => send(sticker: s),
                                    borderRadius: BorderRadius.circular(20),
                                    child: SizedBox(
                                      width: 105,
                                      height: 130,
                                      child: Lottie.asset(
                                        'assets/stickers/$s.json',
                                        animate: !reduced,
                                        repeat: true,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    ),
  );
  Widget message(Msg m) => Align(
    alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReplyBubble(
        key: ValueKey(m.id),
        reduced: reduced,
        onReply: () {
          setState(() => reply = m);
          HapticFeedback.selectionClick();
        },
        onMenu: (position) {
          final box = stageKey.currentContext!.findRenderObject() as RenderBox;
          setState(() {
            menuMsg = m;
            menuAt = box.globalToLocal(position);
            menuAt = Offset(
              menuAt.dx.clamp(24, box.size.width - 24),
              menuAt.dy.clamp(70, box.size.height - 180),
            );
          });
        },
        child: Opacity(
          opacity: m.id == serial && flyingText != null ? 0 : 1,
          child: Container(
            key: m.id == serial ? flyKey : null,
            constraints: const BoxConstraints(maxWidth: 380),
            padding: m.sticker != null
                ? const EdgeInsets.all(2)
                : const EdgeInsets.fromLTRB(13, 10, 11, 7),
            decoration: m.sticker != null
                ? null
                : BoxDecoration(
                    color: m.mine
                        ? const Color(0xff2b5278)
                        : const Color(0xff182533),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(m.mine ? 16 : 4),
                      bottomRight: Radius.circular(m.mine ? 4 : 16),
                    ),
                  ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (m.reply != null)
                  Container(
                    width: 260,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .12),
                      border: const Border(
                        left: BorderSide(color: blue, width: 3),
                      ),
                    ),
                    child: Text(
                      m.reply!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: blue, fontSize: 12),
                    ),
                  ),
                if (m.sticker != null)
                  SizedBox(
                    width: 125,
                    height: 125,
                    child: Lottie.asset(
                      'assets/stickers/${m.sticker}.json',
                      animate: !reduced,
                    ),
                  )
                else
                  Text(
                    m.text,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      fontFamilyFallback: ['ChatEmoji'],
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.reaction != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${m.reaction} 1',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamilyFallback: ['ChatEmoji'],
                          ),
                        ),
                      ),
                    const Text(
                      '21:46',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                    if (m.mine) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all, size: 14, color: blue),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget contextMenu() {
    final box = stageKey.currentContext!.findRenderObject() as RenderBox;
    final x = (menuAt.dx - 110)
        .clamp(14.0, math.max(14.0, box.size.width - 274))
        .toDouble();
    final y = (menuAt.dy - 50)
        .clamp(18.0, math.max(18.0, box.size.height - 250))
        .toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => menuMsg = null),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: reduced ? 0 : 5,
                sigmaY: reduced ? 0 : 5,
              ),
              child: Container(color: Colors.black.withValues(alpha: .38)),
            ),
          ),
        ),
        Positioned(
          left: x,
          top: math.max(8, y - 65),
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff2b5278),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              menuMsg!.text.isEmpty ? '动态贴纸' : menuMsg!.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontFamilyFallback: ['ChatEmoji'],
              ),
            ),
          ),
        ),
        Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .96, end: 1),
            duration: Duration(milliseconds: duration(180)),
            curve: Curves.easeOut,
            builder: (_, v, child) => Transform.scale(
              scale: v,
              alignment: Alignment.topLeft,
              child: child,
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 260,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: const Color(0xff344454)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['❤', '👍', '🔥', '✨', '😁']
                          .map(
                            (e) => InkWell(
                              onTap: () => react(e),
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Text(
                                  e,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontFamily: 'ChatEmoji',
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 230,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        SafeMenuTile(
                          dense: true,
                          leading: const Icon(Icons.reply, color: blue),
                          title: const Text('回复'),
                          onTap: () => setState(() {
                            reply = menuMsg;
                            menuMsg = null;
                          }),
                        ),
                        SafeMenuTile(
                          dense: true,
                          leading: const Icon(
                            Icons.copy_outlined,
                            color: muted,
                          ),
                          title: const Text('复制文字'),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: menuMsg!.text),
                            );
                            setState(() => menuMsg = null);
                          },
                        ),
                        SafeMenuTile(
                          dense: true,
                          leading: const Icon(Icons.close, color: muted),
                          title: const Text('关闭菜单'),
                          onTap: () => setState(() => menuMsg = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReplyBubble extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final ValueChanged<Offset> onMenu;
  final bool reduced;
  const ReplyBubble({
    super.key,
    required this.child,
    required this.onReply,
    required this.onMenu,
    required this.reduced,
  });
  @override
  State<ReplyBubble> createState() => _ReplyBubbleState();
}

class _ReplyBubbleState extends State<ReplyBubble> {
  double dx = 0;
  bool armed = false;
  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: const Duration(milliseconds: 420),
            ),
            (instance) {
              instance.onLongPressStart = (d) =>
                  widget.onMenu(d.globalPosition);
            },
          ),
    },
    child: GestureDetector(
      onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
      onHorizontalDragUpdate: (d) {
        setState(() => dx = (dx + d.delta.dx).clamp(0, 88));
        if (dx > 64 && !armed) {
          armed = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        if (armed) widget.onReply();
        setState(() {
          dx = 0;
          armed = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        dx = 0;
        armed = false;
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 14,
            child: Opacity(
              opacity: (dx / 64).clamp(0, 1),
              child: const Icon(Icons.reply_rounded, color: blue),
            ),
          ),
          AnimatedContainer(
            duration: Duration(
              milliseconds: dx == 0 && !widget.reduced ? 220 : 0,
            ),
            curve: Curves.easeOutBack,
            transform: Matrix4.translationValues(dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    ),
  );
}

class WallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0xff253749).withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double x = 30; x < s.width; x += 92) {
      for (double y = 30; y < s.height; y += 92) {
        c.drawCircle(Offset(x, y), 10, p);
        c.drawLine(Offset(x + 23, y + 30), Offset(x + 35, y + 18), p);
        c.drawLine(Offset(x + 35, y + 18), Offset(x + 43, y + 31), p);
        c.drawLine(Offset(x + 43, y + 31), Offset(x + 23, y + 30), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BurstPainter extends CustomPainter {
  final double t;
  final Offset center;
  final String emoji;
  BurstPainter(this.t, this.center, this.emoji);
  @override
  void paint(Canvas c, Size s) {
    if (t <= 0 || t >= 1) return;
    for (int i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final r = 20 + 100 * Curves.easeOut.transform(t);
      final pos =
          center +
          Offset(math.cos(angle) * r, math.sin(angle) * r + t * t * 40);
      final tp = TextPainter(
        text: TextSpan(
          text: i % 3 == 0 ? emoji : '✦',
          style: TextStyle(
            color: (i % 2 == 0 ? blue : const Color(0xffffcf73)).withValues(
              alpha: 1 - t,
            ),
            fontFamily: 'ChatEmoji',
            fontSize: (i % 3 == 0 ? 24 : 14) * (1 - t * .4),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, pos);
    }
  }

  @override
  bool shouldRepaint(covariant BurstPainter oldDelegate) => oldDelegate.t != t;
}

class SafeMenuTile extends StatelessWidget {
  const SafeMenuTile({
    super.key,
    required this.dense,
    required this.leading,
    required this.title,
    required this.onTap,
  });
  final bool dense;
  final Widget leading, title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    child: ListTile(dense: dense, leading: leading, title: title, onTap: onTap),
  );
}
