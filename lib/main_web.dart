import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/app_identity.dart';
import 'core/app_licenses.dart';
import 'core/browser_received_files.dart';
import 'core/os_privacy.dart';
import 'core/platform_files_web.dart';
import 'theme/tokens.dart';

// The browser runs the same application, screens and state as the native app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  try {
    await BrowserPrivateFiles.initialize();
    // 닫힌 탭이 OPFS에 남긴 수신 파일을 지움 (살아 있는 탭의 것은 Web Lock으로 지킴)
    unawaited(BrowserReceivedFiles.sweepStaleTemp());
    await OsPrivacy.refreshAccessibility();
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
