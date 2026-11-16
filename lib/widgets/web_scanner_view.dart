import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intragram/core/qr_decode.dart';
import 'scanner_frame.dart';
import 'scanner_view.dart';
import 'web_camera.dart';

// 브라우저용 ScannerView 몸통. 앱처럼 화면이 앞에 있을 때만 카메라를 켜고, 탭을 숨기거나 화면을 닫으면
// 바로 놓음 (카메라 표시등이 남지 않게). 해독은 앱과 같은 decodeQr를 프레임 간격마다 한 장씩 돌림
class WebScannerView extends StatefulWidget {
  const WebScannerView({required this.view, super.key});

  // 문구·조준틀·콜백은 ScannerView 설정을 그대로 씀
  final ScannerView view;

  @override
  State<WebScannerView> createState() => _WebScannerViewState();
}

class _WebScannerViewState extends State<WebScannerView>
    with WidgetsBindingObserver {
  static const _frameGap = Duration(milliseconds: 150);

  WebCamera? _camera;
  Timer? _frames;
  bool? _denied;
  bool _opening = false;
  bool _done = false;
  bool _front = true;
  bool _wentAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _done = true;
    _release();
    super.dispose();
  }

  // 권한 창·공유 시트로 잠깐 가려진 것(inactive)은 그대로 둠. 거부는 탭을 떠났다 왔을 때만 다시 물음:
  // 권한 창이 닫히며 오는 복귀마다 다시 열면 같은 질문이 연달아 뜸
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _front = true;
        if (_wentAway) _denied = null;
        _wentAway = false;
        unawaited(_open());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _front = false;
        _wentAway = true;
        _release();
        if (mounted) setState(() {});
    }
  }

  Future<void> _open() async {
    if (_camera != null || _opening || _done || _denied != null) return;
    if (!WebCamera.supported) return _fail(denied: false);
    _opening = true;
    try {
      final camera = await WebCamera.open();
      if (_done || !_front || !mounted) return camera.dispose();
      _camera = camera;
      _frames = Timer.periodic(_frameGap, (_) => _read());
      setState(() {});
    } on WebCameraUnavailable catch (e) {
      _fail(denied: e.denied);
    } finally {
      _opening = false;
    }
  }

  void _fail({required bool denied}) {
    if (mounted) setState(() => _denied = denied);
  }

  void _read() {
    final frame = _camera?.grab();
    if (frame == null || _done) return;
    final raw = decodeQr(frame);
    if (raw == null || !widget.view.onCode(raw)) return;
    _done = true;
    _release();
  }

  void _release() {
    _frames?.cancel();
    _frames = null;
    _camera?.dispose();
    _camera = null;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final denied = _denied;
    if (denied != null) {
      return CameraUnavailable(text: view.noCamera, denied: denied);
    }
    final camera = _camera;
    final size = camera?.size;
    if (camera == null || size == null || size.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return ScannerFrame(
      preview: camera.preview,
      previewSize: size,
      hint: view.hint,
      reticleSide: view.reticleSide,
      reticleRadius: view.reticleRadius,
    );
  }
}
