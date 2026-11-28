import 'package:flutter/foundation.dart';

// 폰·태블릿(Android·iOS) 전용 화면 요소(카메라 스캔, 사진 보관함, 공유 시트) 표시 여부를 결정함.
// dart:io 말고 defaultTargetPlatform이라 기기에선 같은 값이고 위젯 테스트는 호스트와 상관없이 고를 수 있음 (OS API 호출은 dart:io로 가름)
bool get isMobileTarget =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

// macOS·Linux 앱의 Flutter 접근성 브리지는 tooltip을 VoiceOver·Orca 이름으로 안 넘김: 아이콘 버튼·상태 아이콘은 이 두 앱에서만
// 같은 문구를 label로도 붙임. 웹(맥 브라우저 포함)·Windows는 tooltip을 이름으로 읽어 붙이면 두 번 읽힘
// (Flutter도 Android 뒤로 버튼엔 같은 이유로 플랫폼별 label을 붙임)
bool get isMacOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get tooltipNeedsLabel =>
    isMacOSApp || !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
String? tooltipLabel(String name) => tooltipNeedsLabel ? name : null;
