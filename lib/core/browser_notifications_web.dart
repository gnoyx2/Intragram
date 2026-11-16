import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'target_platform.dart';

abstract final class BrowserNotifications {
  static final _active = <String, web.Notification>{};
  // 폰 브라우저는 페이지 알림을 못 띄움: Android Chrome은 서비스 워커 없이 new Notification()이
  // 예외이고 iOS Safari 탭엔 알림 API가 없음. 권한만 묻고 안 뜨는 일이 없게 미지원으로 둠
  static bool get supported {
    if (isMobileTarget) return false;
    try {
      return web.Notification.permission.isNotEmpty;
    } on Object {
      return false;
    }
  }

  static Future<void> request() async {
    if (supported && web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  }

  static void show(
    String title,
    String body,
    String id,
    void Function()? open,
  ) {
    if (!supported || web.Notification.permission != 'granted') return;
    _active.remove(id)?.close();
    final web.Notification notification;
    try {
      notification = web.Notification(
        title,
        web.NotificationOptions(body: body, tag: 'intragram-$id'),
      );
    } on Object {
      // 알림을 못 띄워도 메시지 수신은 계속됨
      return;
    }
    _active[id] = notification;
    notification.onclick = ((web.Event _) {
      web.window.focus();
      notification.close();
      _active.remove(id);
      open?.call();
    }).toJS;
    while (_active.length > 100) {
      _active.remove(_active.keys.first)?.close();
    }
  }

  static void clear() {
    for (final notification in _active.values) {
      notification.close();
    }
    _active.clear();
  }
}
