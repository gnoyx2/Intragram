import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:mime/mime.dart';
import 'package:web/web.dart' as web;

// 웹 빌드 전용이라 조건부 export 대신 웹 구현을 바로 씀 (같은 라이브러리라 받은 파일 목록도 같음)
import 'browser_received_files_web.dart';

// 폰 브라우저의 시스템 공유 시트. 앱의 공유·저장 버튼과 같은 자리를 채움 (사진 앱 저장, 다른 앱으로 보내기).
// 파일 공유를 못 하는 브라우저·형식이면 false라 호출부가 다운로드로 대신함
abstract final class BrowserShare {
  static bool get canShareFiles => _canShare(
    web.ShareData(
      files: <web.File>[
        web.File(
          <JSAny>[].toJS,
          'probe.txt',
          web.FilePropertyBag(type: 'text/plain'),
        ),
      ].toJS,
    ),
  );

  // 탭 처리 중에 바로 불러야 함 (Safari는 사용자 동작 없이 연 공유를 막음)
  static bool shareReceived(String path) {
    final blob = BrowserReceivedFiles.blobOf(path);
    final name = BrowserReceivedFiles.nameOf(path);
    if (blob == null || name == null) return false;
    final file = web.File(
      <JSAny>[blob].toJS,
      name,
      web.FilePropertyBag(
        type: lookupMimeType(name) ?? 'application/octet-stream',
      ),
    );
    final data = web.ShareData(files: <web.File>[file].toJS);
    if (!_canShare(data)) return false;
    // 시트를 그냥 닫으면 AbortError로 끝남: 실패가 아니라 무시함
    unawaited(
      web.window.navigator
          .share(data)
          .toDart
          .then<void>((_) {}, onError: (Object _) {}),
    );
    return true;
  }

  static bool _canShare(web.ShareData data) {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('share') || !navigator.has('canShare')) return false;
    try {
      return web.window.navigator.canShare(data);
    } on Object {
      return false;
    }
  }
}
