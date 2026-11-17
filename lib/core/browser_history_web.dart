import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

// Flutter는 시작하자마자 조작 없이 기록 칸을 하나 더 쌓고, 그 아래 칸으로 돌아오는 걸 뒤로 가기로 받음.
// Firefox는 한 번도 건드리지 않은 칸을 뒤로 가기에서 건너뛰어서 대화 안에서 뒤로를 눌러도 앱이 못 받고
// 페이지를 떠나려 했음: 첫 터치·키 입력이 끝난 뒤에 그 칸을 쌓아서 아래 칸이 건드린 칸이 되게 함
void installFirstTouchHistory() {
  final base = ui_web.urlStrategy;
  if (base == null || base is _FirstTouchUrlStrategy) return;
  ui_web.urlStrategy = _FirstTouchUrlStrategy(base);
}

typedef _Entry = ({Object? state, String title, String url});

final class _FirstTouchUrlStrategy implements ui_web.UrlStrategy {
  _FirstTouchUrlStrategy(this._base);

  final ui_web.UrlStrategy _base;
  // Firefox는 손을 뗀 입력에서 지금 칸을 건드린 칸으로 표시함
  static const _touchEvents = ['pointerup', 'touchend', 'mouseup', 'keyup'];
  bool _firstPushSeen = false;
  // 엔진이 이미 쌓았다고 보는 칸
  _Entry? _pending;
  late final JSFunction _onTouch = ((web.Event _) {
    _stopListening();
    // 그 입력을 브라우저가 다 처리한 다음 차례에 쌓음
    Timer.run(_flush);
  }).toJS;

  @override
  ui.VoidCallback addPopStateListener(ui_web.PopStateListener fn) =>
      _base.addPopStateListener(fn);

  @override
  String getPath() => _base.getPath();

  @override
  Object? getState() {
    final pending = _pending;
    return pending == null ? _base.getState() : pending.state;
  }

  @override
  String prepareExternalUrl(String internalUrl) =>
      _base.prepareExternalUrl(internalUrl);

  @override
  void pushState(Object? state, String title, String url) {
    if (!_firstPushSeen) {
      _firstPushSeen = true;
      _pending = (state: state, title: title, url: url);
      for (final type in _touchEvents) {
        web.window.addEventListener(type, _onTouch, true.toJS);
      }
      return;
    }
    _drop();
    _base.pushState(state, title, url);
  }

  @override
  void replaceState(Object? state, String title, String url) {
    if (_pending != null) {
      _pending = (state: state, title: title, url: url);
      return;
    }
    _base.replaceState(state, title, url);
  }

  @override
  Future<void> go(int count) {
    if (_pending == null || count >= 0) return _base.go(count);
    // 아직 안 쌓은 칸에서 뒤로: 그 한 칸은 이미 돌아온 셈
    _drop();
    return count == -1 ? Future<void>.value() : _base.go(count + 1);
  }

  void _flush() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _base.pushState(pending.state, pending.title, pending.url);
  }

  void _drop() {
    _pending = null;
    _stopListening();
  }

  void _stopListening() {
    for (final type in _touchEvents) {
      web.window.removeEventListener(type, _onTouch, true.toJS);
    }
  }
}
