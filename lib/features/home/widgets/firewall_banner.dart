import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 서버는 떠 있지만 Windows 방화벽이 지금 망의 수신을 막을 때 (ServerState.inboundBlocked). 설정은 Windows 보안의 방화벽 화면을 엶
class FirewallBanner extends StatelessWidget {
  const FirewallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('server.firewallTitle'),
                  style: text.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  s.t('server.firewall'),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('windowsdefender://network/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(s.t('settings.open')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
