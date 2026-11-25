part of '../message_bubble.dart';

// 앱 밖으로 나가는 길이라 바로 안 열고, 브라우저 주소창처럼 퓨니코드로 바꾼 호스트를 보여 주고 물음
// ('google.com@evil.example'처럼 사용자 정보로 가린 주소도 진짜 호스트가 드러남)
Future<void> _confirmOpenLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return;
  var shown = uri.host;
  try {
    shown = Uri.decodeComponent(uri.host);
  } on FormatException {
    // 깨진 퍼센트 인코딩: 인코딩된 그대로 보여 줌
  }
  final host = asciiHost(shown);
  final s = S.of(context);
  final textTheme = Theme.of(context).textTheme;
  final cupertino = isCupertinoDialog(context);
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      cupertino: cupertino,
      title: Text(s.t('link.openTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(host, style: textTheme.titleMedium),
          if (host != shown.toLowerCase()) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.t('link.lookalike')),
          ],
          const SizedBox(height: AppSpacing.sm),
          // 보여 주기만 함: 고르기 복사는 OsPrivacy를 안 거침 (메시지 복사는 말풍선 메뉴로)
          Text(url, style: textTheme.bodySmall),
        ],
      ),
      actions: dialogActions(ctx, [
        AdaptiveDialogAction(
          cupertino: cupertino,
          onPressed: () => Navigator.of(ctx).pop(false),
          label: s.t('common.cancel'),
        ),
        AdaptiveDialogAction(
          cupertino: cupertino,
          emphasis: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          label: s.t('link.open'),
        ),
      ]),
    ),
  );
  if (open ?? false) await NativeOpen.openUrl(url);
}
