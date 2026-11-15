import 'dart:js_interop';
import 'package:web/web.dart' as web;

abstract final class BrowserNotifications {
  static final _active = <String, web.Notification>{};
  static bool get supported {
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
    final notification = web.Notification(
      title,
      web.NotificationOptions(body: body, tag: 'intragram-$id'),
    );
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
