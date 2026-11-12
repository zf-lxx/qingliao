import 'package:flutter/widgets.dart';

import 'message_layout.dart';

/// Compact `HH:mm` in the device local zone.
String formatBubbleStamp(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Wraps bubble content so a corner stamp can sit on the last line.
class BubbleStampStack extends StatelessWidget {
  final Widget child;
  final String stamp;
  final TextStyle? stampStyle;
  final bool sameLine;
  final double stampWidth;
  final double stampHeight;
  final Widget? trailing;
  final double? minWidth;
  const BubbleStampStack({
    super.key,
    required this.child,
    required this.stamp,
    required this.sameLine,
    required this.stampWidth,
    required this.stampHeight,
    this.stampStyle,
    this.trailing,
    this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(
      padding: EdgeInsets.only(bottom: sameLine ? 0 : stampHeight + 2),
      child: sameLine
          ? Padding(
              padding: EdgeInsets.only(
                right: stampWidth + StampLayout.stampGap,
              ),
              child: child,
            )
          : child,
    );
    final floor = minWidth;
    if (floor != null && floor > 0) {
      body = ConstrainedBox(
        constraints: BoxConstraints(minWidth: floor),
        child: body,
      );
    }
    return Stack(
      children: [
        body,
        Positioned(
          right: 0,
          bottom: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stamp,
                key: const Key('native-bubble-stamp'),
                style: stampStyle ?? StampLayout.stampStyle,
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

/// Whether this bubble should drop its tail because a newer neighbor continues
/// the same sender cluster.
bool isClusteredWithNewer({
  required bool sameSender,
  required bool separatedByTimeOrTopic,
  required bool newerIsService,
}) => sameSender && !separatedByTimeOrTopic && !newerIsService;
