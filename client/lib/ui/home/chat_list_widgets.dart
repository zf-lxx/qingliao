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
        height: 72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
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
      _from = ((old.index - widget.index) * 72.0).clamp(-800, 800);
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
  final int selected, badge;
  final ValueChanged<int> onChanged;
  const TgBottomNav({
    super.key,
    required this.selected,
    required this.badge,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(72, 0, 72, 12),
    child: TgGlass(
      radius: 28,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: PressableScale(
                  onTap: () => onChanged(i),
                  radius: 24,
                  child: Center(
                    child: Badge(
                      isLabelVisible: i == 0 && badge > 0,
                      label: Text('$badge'),
                      child: Icon(
                        [
                          Icons.chat_bubble_rounded,
                          Icons.people_alt_rounded,
                          Icons.settings_rounded,
                          Icons.person_rounded,
                        ][i],
                        size: 26,
                        color: selected == i
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xff7d91a5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
