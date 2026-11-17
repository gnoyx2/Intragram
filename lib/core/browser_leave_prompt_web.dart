import 'dart:js_interop';

import 'package:web/web.dart' as web;

// 대화가 있는 동안 새로고침·탭 닫기·다른 주소로 이동하면 브라우저가 한 번 묻게 함. 앱의 떠나기 확인은
// 뒤로 가기만 받고, 화면을 안 건드린 채 뒤로를 연달아 누르면 브라우저가 그 확인을 건너뜀(뒤로 가두기 방지)
abstract final class BrowserLeavePrompt {
  static final JSFunction _ask = ((web.Event event) {
    event.preventDefault();
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;
  static bool _armed = false;

  static void arm(bool on) {
    if (on == _armed) return;
    _armed = on;
    if (on) {
      web.window.addEventListener('beforeunload', _ask);
    } else {
      web.window.removeEventListener('beforeunload', _ask);
    }
  }
}
