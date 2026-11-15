import 'package:flutter/material.dart';
import 'package:intragram/features/portal/web_connection_dialog.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'home_sections.dart';

class WebConnectionCard extends StatelessWidget {
  const WebConnectionCard({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(S.of(context).t('secureWeb.open')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.of(context).t('secureWeb.browserNetwork')),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              icon: const Icon(Icons.add_link),
              onPressed: () => showWebConnectionDialog(context),
              label: Text(S.of(context).t('secureWeb.open')),
            ),
          ],
        ),
      ),
    ],
  );
}
