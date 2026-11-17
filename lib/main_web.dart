import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/app_identity.dart';
import 'core/app_licenses.dart';
import 'core/browser_history_web.dart';
import 'core/browser_received_files.dart';
import 'core/os_privacy.dart';
import 'core/platform_files_web.dart';
import 'theme/tokens.dart';

// The browser runs the same application, screens and state as the native app.
Future<void> main() async {
  // 엔진이 브라우저 기록을 처음 만지기 전에 둬야 함
  installFirstTouchHistory();
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  try {
    await BrowserPrivateFiles.initialize();
    // 닫힌 탭이 OPFS에 남긴 수신 파일을 지움 (살아 있는 탭의 것은 Web Lock으로 지킴)
    unawaited(BrowserReceivedFiles.sweepStaleTemp());
    await OsPrivacy.refreshAccessibility();
    _registerCupertinoFont();
    final identity = await AppIdentity.create();
    runApp(
      ProviderScope(
        overrides: [appIdentityProvider.overrideWithValue(identity)],
        child: const IntragramApp(),
      ),
    );
  } on Object {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '브라우저 저장소를 열지 못했습니다. 기존 보관소를 보호하기 위해 시작을 중단했습니다.\n'
                    'Browser storage is unavailable. Your existing archive has not been overwritten.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: main,
                    child: const Text('다시 시도 · Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// iPhone·Mac 브라우저의 Cupertino 대화상자는 테마 글꼴 대신 CupertinoSystemText를 고정으로 씀.
// 웹 번들엔 그 글꼴이 없어서 한글이 □로 나왔음: 앱 글꼴을 그 이름으로도 등록함 (앱은 OS 시스템 글꼴을 씀).
// 그 대화상자가 뜨는 Apple 기기에서만, 첫 화면을 막지 않게 뒤에서 올림 (글꼴이 10MB라 메모리를 더 씀)
void _registerCupertinoFont() {
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS) {
    return;
  }
  final loader = FontLoader('CupertinoSystemText')
    ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
  // 못 올리면 대화상자 한글만 예전처럼 빠짐: 앱 시작은 그대로 둠
  unawaited(loader.load().catchError((Object _) {}));
}
