import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat_engine.dart';
import '../../widgets/image_viewer.dart';
import '../home/chat_list_widgets.dart';
import '../motion/tg_motion.dart';
import '../theme/tg_tokens.dart';

/// Cached media is explicitly labelled; not a substitute for a paginated server index.
class ChatInfoPage extends StatefulWidget {
  final ChatEngine engine;
  final String cid, title;
  final List<Json> members;
  final Widget Function(double) avatarBuilder;
  final VoidCallback onSearch;
  const ChatInfoPage({
    super.key,
    required this.engine,
    required this.cid,
    required this.title,
    required this.members,
    required this.avatarBuilder,
    required this.onSearch,
  });
  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  late List<Json> members;
  String? loadError;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    members = widget.members;
    _load();
  }

  Future<void> _load() async {
    final e = widget.engine;
    if (e.api == null) {
      loading = false;
      return;
    }
    try {
      final result = objects(
        (await e.api!.call(
          'GET',
          '/conversations/${widget.cid}/members',
        ))['members'],
      );
      final list = <Json>[];
      for (final m in result) {
        list.add({...m, ...await e.user(m['user_id'])});
      }
      if (mounted) {
        setState(() {
          members = list;
          loading = false;
          loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = '资料暂不可用，点击重试';
        });
      }
    }
  }

  String tab = 'media';
  final Map<String, Future<Uint8List>> media = {};
  @override
  Widget build(BuildContext context) {
    final e = widget.engine, history = e.history(widget.cid);
    final images = history
        .where(
          (m) =>
              m['kind'] == 'image' &&
              m['deleted'] != true &&
              m['media_id'] != null,
        )
        .toList()
        .reversed
        .toList();
    final links = history
        .where((m) => m['deleted'] != true && m['link_preview'] != null)
        .toList()
        .reversed
        .toList();
    final peer = members.where((m) => m['id'] != e.uid).firstOrNull;
    final group = e.dialogs[widget.cid]?['kind'] == 'group';
    final muted =
        number(e.dialogs[widget.cid]?['notification_mute_until']) >
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final style = const TextStyle(color: TgTokens.muted, fontSize: 12);
    Widget action(IconData icon, String label, VoidCallback tap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: PressableScale(
          onTap: tap,
          radius: TgTokens.cardRadius,
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: TgTokens.card,
              borderRadius: BorderRadius.circular(TgTokens.cardRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: TgTokens.accent),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: TgTokens.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: TgTokens.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 255,
            backgroundColor: TgTokens.background,
            leading: TgIconButton(
              tooltip: '返回',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.title, style: const TextStyle(fontSize: 17)),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Hero(
                      tag: 'chat-avatar-${widget.cid}',
                      child: widget.avatarBuilder(55),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      loading
                          ? '加载资料中…'
                          : group
                          ? '${members.length} 名成员'
                          : peer?['online'] == true
                          ? '在线'
                          : '云端聊天',
                      style: style,
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
          if (loadError != null)
            SliverToBoxAdapter(
              child: TextButton(onPressed: _load, child: Text(loadError!)),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      action(
                        Icons.chat_bubble_outline_rounded,
                        '消息',
                        () => Navigator.pop(context),
                      ),
                      action(
                        muted
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        muted ? '取消静音' : '静音',
                        () async {
                          try {
                            await e.state(widget.cid, {
                              'mute_until': muted ? '' : 'forever',
                            });
                            if (mounted) setState(() {});
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                      ),
                      action(Icons.search_rounded, '搜索', () {
                        Navigator.pop(context);
                        widget.onSearch();
                      }),
                    ],
                  ),
                  const SizedBox(height: TgTokens.blockGap),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: TgTokens.card,
                      borderRadius: BorderRadius.circular(TgTokens.cardRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!group && peer?['handle'] != null) ...[
                          Text(
                            '@${peer!['handle']}',
                            style: const TextStyle(
                              color: TgTokens.accent,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('用户名', style: style),
                          const SizedBox(height: 12),
                        ],
                        if ((peer?['bio'] ?? '').toString().isNotEmpty)
                          Text('${peer!['bio']}'),
                        Text('服务器可访问消息内容 · 非端到端加密', style: style),
                      ],
                    ),
                  ),
                  const SizedBox(height: TgTokens.blockGap),
                  if (group)
                    Container(
                      decoration: BoxDecoration(
                        color: TgTokens.card,
                        borderRadius: BorderRadius.circular(
                          TgTokens.cardRadius,
                        ),
                      ),
                      child: Column(
                        children: [
                          for (final u in members)
                            ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (u['display_name'] ?? u['handle'] ?? '?')
                                      .toString()
                                      .characters
                                      .first,
                                ),
                              ),
                              title: Text(
                                u['display_name'] ?? u['handle'] ?? '成员',
                              ),
                              subtitle: Text(
                                '${u['role'] ?? '成员'}',
                                style: style,
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: TgTokens.blockGap),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _MediaTabs(
              TgGlass(
                radius: 0,
                child: TgFolderTabs(
                  tabs: [
                    (id: 'media', label: '媒体', count: images.length),
                    (id: 'links', label: '链接', count: links.length),
                  ],
                  selected: tab,
                  onSelected: (id) => setState(() => tab = id),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Text('${images.length} 张本机已加载图片 · 非全部历史统计', style: style),
            ),
          ),
          if (tab == 'media' && images.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(2),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final m = images[index], id = m['media_id'] as String;
                  return FutureBuilder<Uint8List>(
                    future: media.putIfAbsent(id, () => e.api!.media(id)),
                    builder: (context, snapshot) => PressableScale(
                      radius: 0,
                      onTap: snapshot.hasData
                          ? () => openImageViewer(
                              context,
                              bytes: snapshot.data!,
                              tag: 'shared-${m['id']}',
                              sender: widget.title,
                              time: '',
                            )
                          : null,
                      child: Hero(
                        tag: 'shared-${m['id']}',
                        child: snapshot.hasData
                            ? Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                cacheWidth: 450,
                              )
                            : ColoredBox(
                                color: TgTokens.card,
                                child: Center(
                                  child: Icon(
                                    snapshot.hasError
                                        ? Icons.broken_image_outlined
                                        : Icons.image_outlined,
                                    color: TgTokens.muted,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                }, childCount: images.length),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
              ),
            )
          else if (tab == 'links' && links.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final preview = obj(links[i]['link_preview']);
                return ListTile(
                  leading: const Icon(
                    Icons.link_rounded,
                    color: TgTokens.accent,
                  ),
                  title: Text(preview['title'] ?? ''),
                  subtitle: Text(preview['url'] ?? links[i]['text'] ?? ''),
                );
              }, childCount: links.length),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    '尚无已加载的内容',
                    style: TextStyle(color: TgTokens.muted),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }
}

class _MediaTabs extends SliverPersistentHeaderDelegate {
  final Widget child;
  _MediaTabs(this.child);
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(_MediaTabs old) => true;
}
