import 'package:flutter/material.dart';

import '../motion/tg_motion.dart';
import '../theme/tg_tokens.dart';

class TgUnreadBadge extends StatelessWidget {
  final int count;
  final bool muted;
  const TgUnreadBadge(this.count, {super.key, this.muted = false});
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: const TgOvershoot(),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 430),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .65, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: count <= 0
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Container(
              key: ValueKey(count),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: muted
                    ? const Color(0xffa9b1bb)
                    : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count > 999 ? '999+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    ),
  );
}

class TgFolderTabs extends StatelessWidget {
  final List<({String id, String label, int count})> tabs;
  final String selected;
  final ValueChanged<String> onSelected;
  const TgFolderTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .copyWith(fontWeight: FontWeight.w600, fontSize: 15);
    final widths = tabs.map((tab) {
      final t = TextPainter(
        text: TextSpan(text: tab.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final badge = TextPainter(
        text: TextSpan(
          text: tab.count > 999 ? '999+' : '${tab.count}',
          style: style.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final badgeWidth = badge.width + 12 < 22 ? 22.0 : badge.width + 12;
      return t.width + 28 + (tab.count > 0 ? badgeWidth + 6 : 0);
    }).toList();
    final index = tabs.indexWhere((t) => t.id == selected);
    final target = index < 0 ? 0 : index;
    final left = widths.take(target).fold<double>(0, (a, b) => a + b + 7);
    final color = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
      child: SizedBox(
        height: 36,
        width: widths.fold<double>(0, (a, b) => a + b) + 7 * (tabs.length - 1),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: tgEaseOutQuint,
              left: left,
              top: 0,
              width: widths[target],
              height: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: tgEaseOutQuint,
              left: left + widths[target] / 2 - 10,
              bottom: 6,
              width: 20,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == tabs.length - 1 ? 0 : 7,
                    ),
                    child: SizedBox(
                      width: widths[i],
                      height: 36,
                      child: PressableScale(
                        radius: 24,
                        onTap: () => onSelected(tabs[i].id),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: style.copyWith(
                                color: i == target
                                    ? color
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                              child: Text(tabs[i].label),
                            ),
                            if (tabs[i].count > 0) ...[
                              const SizedBox(width: 6),
                              TgUnreadBadge(tabs[i].count, muted: i != target),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TgChatRow extends StatelessWidget {
  final Widget avatar;
  final String title, preview, time;
  final int unread;
  final bool pinned, muted, mention, outgoing, read, draft;
  final VoidCallback onTap, onLongPress;
  const TgChatRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.preview,
    required this.time,
    required this.unread,
    required this.onTap,
    required this.onLongPress,
    this.pinned = false,
    this.muted = false,
    this.mention = false,
    this.outgoing = false,
    this.read = false,
    this.draft = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: pinned
        ? Theme.of(context).colorScheme.primary.withValues(alpha: .035)
        : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashFactory: InkRipple.splashFactory,
      child: SizedBox(
        // DialogCell heightDefault = 70dp; avatarStart 11, paddingStart 72.
        height: 70,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 0, 16, 0),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (muted)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.volume_off_rounded,
                              size: 14,
                              color: Color(0xff7d91a5),
                            ),
                          ),
                        if (outgoing)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Icon(
                              read
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0
                                ? Theme.of(context).colorScheme.primary
                                : const Color(0xff7d91a5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: draft
                                  ? const Color(0xff5dade6)
                                  : const Color(0xff7d91a5),
                            ),
                          ),
                        ),
                        if (mention)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.alternate_email_rounded,
                              size: 21,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        if (unread > 0)
                          TgUnreadBadge(unread, muted: muted)
                        else if (pinned)
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: Colors.grey,
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
    ),
  );
}

/// Keeps keyed lazy-list rows alive during a server driven reorder.
class TgReorderItem extends StatefulWidget {
  final int index;
  final Widget child;
  const TgReorderItem({super.key, required this.index, required this.child});
  @override
  State<TgReorderItem> createState() => _TgReorderItemState();
}

class _TgReorderItemState extends State<TgReorderItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TgDuration.item,
  )..forward();
  double _from = 0;
  @override
  void didUpdateWidget(TgReorderItem old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = ((old.index - widget.index) * 70.0).clamp(-800, 800);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(
        0,
        _from * (1 - Curves.decelerate.transform(_controller.value)),
      ),
      child: child,
    ),
  );
}

class TgBottomNav extends StatelessWidget {
  static const labels = ['聊天', '联系人', '设置', '个人资料'];
  static const icons = [
    Icons.chat_bubble_outline_rounded,
    Icons.people_outline_rounded,
    Icons.settings_outlined,
    Icons.person_outline_rounded,
  ];
  static const selectedIcons = [
    Icons.chat_bubble_rounded,
    Icons.people_rounded,
    Icons.settings_rounded,
    Icons.person_rounded,
  ];
  final int selected, badge;
  final ValueChanged<int> onChanged;
  const TgBottomNav({
    super.key,
    required this.selected,
    required this.badge,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: TgTokens.card,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: i == 0 && badge > 0,
                          label: Text('$badge'),
                          child: Icon(
                            selected == i ? selectedIcons[i] : icons[i],
                            size: 24,
                            color: selected == i ? color : TgTokens.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.1,
                            fontWeight: selected == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected == i ? color : TgTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TgSectionHeader extends StatelessWidget {
  final String text;
  const TgSectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    alignment: Alignment.bottomLeft,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    color: TgTokens.background,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: TgTokens.accent,
      ),
    ),
  );
}

class TgSettingsCell extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? value, subtitle;
  final bool destructive, divider;
  final Widget? trailing;
  final VoidCallback? onTap;
  const TgSettingsCell({
    super.key,
    this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.destructive = false,
    this.divider = true,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final tall = subtitle != null;
    return Material(
      color: TgTokens.card,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tall ? 64 : 50),
          child: CustomPaint(
            painter: divider ? const _CellDivider() : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 24,
                      color: destructive
                          ? const Color(0xffe05c5c)
                          : TgTokens.accent,
                    ),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            color: destructive
                                ? const Color(0xffe05c5c)
                                : const Color(0xffeef4fa),
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.25,
                                color: TgTokens.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        value!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: TgTokens.muted,
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TgCheckCell extends StatelessWidget {
  final String title, subtitle;
  final bool value, divider;
  final ValueChanged<bool>? onChanged;
  const TgCheckCell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    this.divider = true,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: TgTokens.card,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: CustomPaint(
        painter: divider ? const _CellDivider() : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xffeef4fa),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TgTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    ),
  );
}

class TgUserRow extends StatelessWidget {
  final Widget avatar;
  final String name, status;
  final bool online, divider;
  final VoidCallback? onTap;
  const TgUserRow({
    super.key,
    required this.avatar,
    required this.name,
    required this.status,
    this.online = false,
    this.divider = true,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: TgTokens.card,
    child: InkWell(
      onTap: onTap,
      child: CustomPaint(
        painter: divider ? const _CellDivider(indent: 72) : null,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 0, 16, 0),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: online
                              ? Theme.of(context).colorScheme.primary
                              : TgTokens.muted,
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
  );
}

class _CellDivider extends CustomPainter {
  final double indent;
  const _CellDivider({this.indent = 16});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(indent, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = const Color(0x14ffffff)
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_CellDivider old) => indent != old.indent;
}
