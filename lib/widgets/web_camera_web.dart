import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'package:intragram/core/qr_decode.dart';

// 카메라를 못 엶. denied면 사용자·브라우저가 권한을 막은 것 (나머지는 카메라 없음·다른 앱이 사용 중)
final class WebCameraUnavailable implements Exception {
  const WebCameraUnavailable({required this.denied});
  final bool denied;
}

// 브라우저 뒤 카메라(getUserMedia). 미리보기는 <video> 플랫폼 뷰이고 프레임은 캔버스로 떠서
// 앱 스캐너와 같은 밝기 평면(QrFrame)으로 넘김. 프레임은 메모리에서 읽고 바로 버림
final class WebCamera {
  WebCamera._(this._stream, this._video);

  // 긴 변을 이만큼까지 줄여 읽음: 조준틀을 채운 IGW1 QR(약 125모듈)이 모듈당 5px쯤 남고 프레임 변환은 가벼움
  static const _maxSide = 1600;

  final web.MediaStream _stream;
  final web.HTMLVideoElement _video;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();

  static bool get supported {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('mediaDevices')) return false;
    return (web.window.navigator.mediaDevices as JSObject).has('getUserMedia');
  }

  static Future<WebCamera> open() async {
    final web.MediaStream stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: false.toJS,
              video: {
                'facingMode': {'ideal': 'environment'},
                'width': {'ideal': 1920},
                'height': {'ideal': 1080},
              }.jsify()!,
            ),
          )
          .toDart;
    } on Object catch (error) {
      // DOMException 이름이 문자열 앞에 옴 (예: "NotAllowedError: ...")
      final text = error.toString();
      throw WebCameraUnavailable(
        denied:
            text.contains('NotAllowedError') || text.contains('SecurityError'),
      );
    }
    // iOS Safari는 playsinline·muted가 없으면 전체 화면으로 열거나 재생을 막음
    final video = web.HTMLVideoElement()
      ..muted = true
      ..autoplay = true
      ..playsInline = true
      ..srcObject = stream;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..pointerEvents = 'none';
    try {
      await video.play().toDart;
    } on Object {
      _stop(stream);
      throw const WebCameraUnavailable(denied: false);
    }
    return WebCamera._(stream, video);
  }

  Widget get preview => HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) => (element as web.HTMLElement).append(_video),
  );

  Size get size =>
      Size(_video.videoWidth.toDouble(), _video.videoHeight.toDouble());

  QrFrame? grab() {
    final w = _video.videoWidth, h = _video.videoHeight;
    if (w == 0 || h == 0) return null;
    final scale = math.min(1.0, _maxSide / math.max(w, h));
    final cw = (w * scale).round(), ch = (h * scale).round();
    _canvas
      ..width = cw
      ..height = ch;
    final context =
        _canvas.getContext('2d', {'willReadFrequently': true}.jsify())
            as web.CanvasRenderingContext2D?;
    if (context == null) return null;
    context.drawImage(_video, 0, 0, cw, ch);
    final rgba = context.getImageData(0, 0, cw, ch).data.toDart;
    final luma = Uint8List(cw * ch);
    for (var i = 0, p = 0; i < luma.length; i++, p += 4) {
      luma[i] = (rgba[p] * 77 + rgba[p + 1] * 150 + rgba[p + 2] * 29) >> 8;
    }
    return QrFrame(luma: luma, width: cw, height: ch, rowStride: cw);
  }

  void dispose() {
    _stop(_stream);
    _video
      ..pause()
      ..srcObject = null
      ..remove();
  }

  static void _stop(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }
}
