import 'package:flutter/material.dart';

import '../ui/theme/tg_tokens.dart';
import 'bubble_path.dart';
import 'message_layout.dart';

/// Text bubble with the timestamp (and ticks) reserved on the last line via a
/// trailing spacer, then painted in the corner. Incoming/outgoing still use
/// the shared path. Not a copy of Telegram source.
class TextMessageCell extends StatelessWidget {
  final String text, stamp;
  final bool mine, grouped, pending, failed, read, edited;
  final Widget? textWidget, quote, reactions;
  final int? groupReads;
  final bool selected;
  const TextMessageCell({
    super.key,
    required this.text,
    required this.stamp,
    required this.mine,
    this.grouped = false,
    this.pending = false,
    this.failed = false,
    this.read = false,
    this.edited = false,
    this.selected = false,
    this.textWidget,
    this.quote,
    this.reactions,
    this.groupReads,
  });

  static String formatStamp(String? createdAt) {
    final date = DateTime.tryParse(createdAt ?? '');
    final china = date?.toUtc().add(const Duration(hours: 8));
    if (china == null) return '';
    final h = china.hour.toString().padLeft(2, '0');
    final m = china.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final checks = mine ? 18.0 : 0.0;
    final stampLabel = edited ? '已编辑 · $stamp' : stamp;
    final theme = Theme.of(context);
    final bodyFamily = theme.textTheme.bodyMedium?.fontFamily;
    final bodyFallback = theme.textTheme.bodyMedium?.fontFamilyFallback;
    final stampTextStyle = StampLayout.stampStyle.copyWith(
      fontFamily: bodyFamily,
      fontFamilyFallback: bodyFallback,
    );
    final bodyTextStyle = StampLayout.textStyle.copyWith(
      fontFamily: bodyFamily,
      fontFamilyFallback: bodyFallback,
    );
    final layout = StampLayout.measure(
      text: text,
      stamp: stampLabel,
      viewportWidth: MediaQuery.sizeOf(context).width,
      grouped: grouped,
      checksWidth: checks,
      headerHeight: (quote == null ? 0 : 44) + (reactions == null ? 0 : 28),
      textStyle: bodyTextStyle,
      stampStyle: stampTextStyle,
    );
    final innerW =
        layout.bubbleWidth -
        StampLayout.padLeft -
        StampLayout.padRight -
        (grouped ? 0 : StampLayout.tail);
    return Align(
      key: const Key('native-text-cell'),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: layout.bubbleWidth,
          maxWidth: layout.bubbleWidth + 8,
        ),
        child: CustomPaint(
          painter: QingliaoBubblePainter(
            mine: mine,
            grouped: grouped,
            color: selected
                ? (mine ? TgTokens.outgoingSelected : TgTokens.incomingSelected)
                : (mine ? TgTokens.outgoing : TgTokens.card),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              StampLayout.padLeft + (mine || grouped ? 0 : StampLayout.tail),
              StampLayout.padTop,
              StampLayout.padRight + (mine && !grouped ? StampLayout.tail : 0),
              StampLayout.padBottom,
            ),
            child: SizedBox(
              width: innerW,
              child: Stack(
                children: [
                  Padding(
                    padding: layout.sameLine
                        ? EdgeInsets.only(top: quote == null ? 0 : 44)
                        : EdgeInsets.only(
                            top: quote == null ? 0 : 44,
                            bottom: layout.stampHeight + 2,
                          ),
                    child: Semantics(
                      label: text,
                      child:
                          textWidget ??
                          Text(
                            text,
                            key: const Key('native-text'),
                            style: bodyTextStyle,
                          ),
                    ),
                  ),
                  if (quote != null)
                    Positioned(left: 0, right: 0, top: 0, child: quote!),
                  if (reactions != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: layout.stampHeight + 2,
                      child: reactions!,
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(stampLabel, style: stampTextStyle),
                        if (mine) ...[
                          const SizedBox(width: 3),
                          Icon(
                            failed
                                ? Icons.error_outline
                                : pending
                                ? Icons.schedule
                                : read
                                ? Icons.done_all
                                : Icons.check,
                            color: failed
                                ? Colors.orangeAccent
                                : TgTokens.accent,
                            size: 14,
                          ),
                        ],
                        if (groupReads != null)
                          Text(' $groupReads人已读', style: stampTextStyle),
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
}

String? defaultTargetPlatformFont(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.fontFamily;
}

/// Trailing spacer so the last line of [EntityText] leaves room for the stamp.
class StampSuffix extends StatelessWidget {
  final double width, height;
  const StampSuffix({super.key, required this.width, required this.height});
  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: height);
}
