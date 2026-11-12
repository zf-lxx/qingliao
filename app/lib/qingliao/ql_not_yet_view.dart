//
//  ql_not_yet_view.dart — Placeholder for settings that need a later server API.
//
//  The row stays in Mithka's Settings layout; opening it must not pretend the
//  feature works or persist a fake success.
//

import 'package:flutter/material.dart';

import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class QlNotYetView extends StatelessWidget {
  const QlNotYetView({
    super.key,
    required this.titleKey,
    this.showBackButton = true,
  });

  final String titleKey;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: titleKey,
      showBackButton: showBackButton,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStringKeys.settingsNotYet.l10n(context),
                textAlign: TextAlign.center,
                style: AppTextStyle.title(c.textPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStringKeys.settingsNotYetMessage.l10n(context),
                textAlign: TextAlign.center,
                style: AppTextStyle.body(c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
