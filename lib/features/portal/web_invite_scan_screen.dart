import 'package:flutter/material.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/target_platform.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/picker_feedback.dart';
import 'package:intragram/widgets/scanner_view.dart';

// 폰 브라우저의 초대 코드 스캔 (앱의 기기 코드 스캔 자리). IGW1 코드가 아닌 QR은 무시하고 계속 스캔함.
// 카메라를 못 쓰는 경우를 위해 이미지에서 읽기도 같은 화면에 둠
class WebInviteScanScreen extends StatefulWidget {
  const WebInviteScanScreen({super.key});

  @override
  State<WebInviteScanScreen> createState() => _WebInviteScanScreenState();
}

class _WebInviteScanScreenState extends State<WebInviteScanScreen> {
  bool _onCode(String raw) {
    final code = raw.trim();
    if (!code.startsWith('IGW1.') || !mounted) return false;
    AppHaptics.mediumImpact();
    Navigator.of(context).pop(code);
    return true;
  }

  Future<void> _fromImage() async {
    final raw = await pickQrImageOrExplain(context);
    if (raw != null && mounted) Navigator.of(context).pop(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 초대 QR은 촘촘해서 조준틀을 기기 코드보다 크게 잡음
    final reticleSide = (MediaQuery.sizeOf(context).shortestSide * 0.78)
        .clamp(200, 320)
        .toDouble();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('secureWeb.scanInvite')),
        actions: [
          IconButton(
            icon: Icon(
              Icons.image_outlined,
              semanticLabel: tooltipLabel(s.t('secureWeb.readQrImage')),
            ),
            tooltip: s.t('secureWeb.readQrImage'),
            onPressed: _fromImage,
          ),
        ],
      ),
      body: ScannerView(
        onCode: _onCode,
        hint: s.t('secureWeb.scanInviteHint'),
        noCamera: s.t('secureWeb.scanNoCamera'),
        reticleSide: reticleSide,
        reticleRadius: AppRadius.lg,
      ),
    );
  }
}
