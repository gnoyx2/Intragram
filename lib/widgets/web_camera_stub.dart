import 'package:flutter/widgets.dart';

import 'package:intragram/core/qr_decode.dart';

final class WebCameraUnavailable implements Exception {
  const WebCameraUnavailable({required this.denied});
  final bool denied;
}

// 앱 빌드에선 안 씀 (앱은 camera 플러그인의 프레임 스트림을 씀)
final class WebCamera {
  WebCamera._();

  static bool get supported => false;

  static Future<WebCamera> open() =>
      Future<WebCamera>.error(const WebCameraUnavailable(denied: false));

  Widget get preview => const SizedBox.shrink();
  Size get size => Size.zero;
  QrFrame? grab() => null;
  void dispose() {}
}
