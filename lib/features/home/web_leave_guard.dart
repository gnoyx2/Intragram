import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 앱은 홈에서 뒤로 가도 대화가 이어지지만 브라우저는 페이지를 떠나며 연결된 대화를 모두 잃음
// (Android 뒤로 가기, iOS 가장자리 스와이프, 브라우저 뒤로 버튼). 대화가 있으면 한 번 묻고 나가기를 고를 때만 떠남
class WebLeaveGuard extends ConsumerWidget {
  const WebLeaveGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;
    final hasChats =
        ref.watch(conversationsProvider).value?.isNotEmpty ?? false;
    return PopScope(
      canPop: !hasChats,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmLeave(context)) return;
        await SystemNavigator.pop();
      },
      child: child,
    );
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        cupertino: cupertino,
        title: Text(s.t('secureWeb.leaveTitle')),
        content: Text(s.t('secureWeb.leaveBody')),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('secureWeb.leaveStay'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            destructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('secureWeb.leave'),
          ),
        ]),
      ),
    );
    return leave ?? false;
  }
}
