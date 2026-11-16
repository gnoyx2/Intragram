import 'package:flutter/material.dart';

import 'package:intragram/theme/tokens.dart';
import 'package:intragram/theme/adaptive_layout.dart';

// 켜진 카메라 미리보기를 화면에 꽉 채우고 가운데 조준틀과 아래 안내를 얹음
class ScannerFrame extends StatelessWidget {
  const ScannerFrame({
    required this.preview,
    required this.previewSize,
    required this.hint,
    required this.reticleSide,
    required this.reticleRadius,
    super.key,
  });

  // 앱은 CameraPreview, 브라우저는 <video> 플랫폼 뷰
  final Widget preview;
  // 화면 방향 기준 크기 (센서 기준 가로 크기는 호출부가 세로 화면에서 뒤집어 넘김)
  final Size previewSize;
  final String hint;
  final double reticleSide;
  final double reticleRadius;

  @override
  Widget build(BuildContext context) {
    final fold = tabletopFold(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 본문 안 MediaQuery는 위 여백(상태 표시줄)이 지워져 있어서 Scaffold가 잰 앱바 높이(상태 표시줄 포함)를 씀
        final origin = Scaffold.maybeOf(context)?.appBarMaxHeight ?? 0;
        final top = fold == null
            ? constraints.maxHeight
            : (fold.bounds.top - origin).clamp(0.0, constraints.maxHeight);
        final bottom = fold == null
            ? 0.0
            : (fold.bounds.bottom - origin).clamp(0.0, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 넘치는 쪽은 잘림
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox.fromSize(size: previewSize, child: preview),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      width: reticleSide,
                      height: reticleSide,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70, width: 3),
                        borderRadius: BorderRadius.circular(reticleRadius),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: fold == null ? null : bottom,
              left: AppSpacing.xxl,
              right: AppSpacing.xxl,
              bottom: fold == null ? AppSpacing.huge : 0,
              child: SingleChildScrollView(
                padding: fold == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
