import 'dart:async';

import 'package:flutter/services.dart';

// iOS 알림, Android registerScreenCaptureCallback(API 34+)로 감지함. iOS는 막을 순 없고 감지만 되며,
// Android 14 미만은 감지도 안 됨. macOS·Windows·Linux·웹은 감지하지 않음 (macOS 이유는 MainFlutterWindow.swift)
class ScreenshotDetector {
  ScreenshotDetector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('intragram/screenshot') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<void> _events = StreamController<void>.broadcast();

  Stream<void> get onScreenshot => _events.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'onScreenshot' && !_events.isClosed) _events.add(null);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _events.close();
  }
}
