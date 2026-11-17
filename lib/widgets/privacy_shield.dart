import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:intragram/core/target_platform.dart';

// 앱이 비활성/숨김일 때 화면 전체를 블러로 덮음. 앱 전환기 스냅샷용 native 커버
// (Android FLAG_SECURE, iOS AppDelegate 불투명 커버)가 못 막는 경우의 보조 수단임.
// 데스크톱은 포커스만 잃어도 inactive라 hidden/paused에서만 덮음. 폰 브라우저도 같음: 권한 창·공유 시트·
// 파일 선택 창만 떠도 inactive가 되고 닫힌 뒤 브라우저가 포커스를 바로 안 돌려줘서 화면을 한 번 누를 때까지
// 흐림이 남음(그 탭이 밑의 버튼을 누름). 탭이 실제로 숨겨질 때만 덮음
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({required this.child, this.web = kIsWeb, super.key});

  final Widget child;
  // 위젯 테스트(VM)가 브라우저 쪽 동작을 돌리는 자리
  final bool web;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield> {
  late final AppLifecycleListener _listener;
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onStateChange);
  }

  void _onStateChange(AppLifecycleState state) {
    final obscured = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.detached => false,
      AppLifecycleState.inactive => isMobileTarget && !widget.web,
      AppLifecycleState.hidden || AppLifecycleState.paused => true,
    };
    if (obscured != _obscured) setState(() => _obscured = obscured);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_obscured)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.7),
            ),
          ),
        ),
    ],
  );
}
