part of '../image_viewer_screen.dart';

// 공유는 모바일만 (폰 브라우저는 브라우저 공유 시트, 못 하면 다운로드). iPad 공유 팝오버가 이 버튼을 가리키게 버튼의 context를 넘김
class _ViewerTopBar extends StatelessWidget {
  const _ViewerTopBar({required this.path, required this.canShare});

  final String path;
  final bool canShare;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        IconButton(
          icon: Icon(
            Icons.close,
            color: Colors.white,
            semanticLabel: macOSAppName(s.t('viewer.close')),
          ),
          tooltip: s.t('viewer.close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        if (canShare)
          Builder(
            builder: (buttonContext) => IconButton(
              icon: Icon(
                Icons.share_outlined,
                color: Colors.white,
                semanticLabel: macOSAppName(s.t('viewer.share')),
              ),
              tooltip: s.t('viewer.share'),
              onPressed: () {
                if (kIsWeb) {
                  if (!BrowserShare.shareReceived(path)) {
                    BrowserReceivedFiles.save(path);
                  }
                  return;
                }
                SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(path)],
                    sharePositionOrigin: shareOrigin(buttonContext),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
