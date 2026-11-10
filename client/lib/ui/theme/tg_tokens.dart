import 'dart:ui';

import 'package:flutter/material.dart';

/// Qingliao tokens: independent design choices, not imported Telegram assets.
abstract final class TgTokens {
  static const background = Color(0xff0e1621),
      card = Color(0xff17212b),
      raised = Color(0xff22303d),
      accent = Color(0xff5dade6),
      muted = Color(0xff7d91a5);
  static const pill = 100.0,
      cardRadius = 20.0,
      smallRadius = 11.0,
      blockGap = 12.0,
      pageInset = 16.0;
  static const blur = 12.0;
}

class TgGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? margin, padding;
  const TgGlass({
    super.key,
    required this.child,
    this.radius = TgTokens.pill,
    this.margin,
    this.padding,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin ?? EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: TgTokens.blur, sigmaY: TgTokens.blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: TgTokens.raised.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: .035)),
          ),
          child: child,
        ),
      ),
    ),
  );
}
