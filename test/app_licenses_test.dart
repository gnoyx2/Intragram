import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_licenses.dart';
import 'package:intragram/features/settings/settings_screen.dart';

import 'ui/_harness.dart';

void main() {
  testWidgets('the license page lists Intragram and the LocalSend notice', (
    tester,
  ) async {
    registerAppLicenses();
    final entries = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    final ours = entries!.where((e) => e.packages.contains('Intragram'));
    final text = ours.expand((e) => e.paragraphs).map((p) => p.text).join('\n');
    expect(text, contains('MIT License'));
    expect(text, contains('Apache License'));
    expect(text, contains('Tien Do Nam'));
    expect(entries.any((e) => e.packages.contains('LocalSend')), isTrue);
  });

  // 네이티브 빌드는 WebRTC 바이너리를 같이 실음: BSD 고지 전문이 그 이름으로 화면에 나와야 함
  testWidgets('the license page lists WebRTC with its license text', (
    tester,
  ) async {
    registerAppLicenses();
    final entries = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    final webrtc = entries!.where((e) => e.packages.contains('WebRTC'));
    final text = webrtc
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(text, contains('The WebRTC project authors'));
    expect(text, contains('Redistributions in binary form must reproduce'));
  });

  // 프리빌트 WebRTC가 품은 하위 구성요소(BoringSSL·libvpx·Opus 등)도 각자 라이선스 전문으로 등록돼야 함
  testWidgets(
    'the license page lists WebRTC third-party components with their license texts',
    (tester) async {
      registerAppLicenses();
      final entries = await tester.runAsync(
        () => LicenseRegistry.licenses.toList(),
      );
      String textFor(String package) => entries!
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');

      expect(
        textFor('BoringSSL'),
        contains('BoringSSL (i.e. libcrypto and libssl)'),
      );
      expect(textFor('libvpx'), contains('The WebM Project authors'));
      expect(textFor('Opus'), contains('Xiph.Org, Skype Limited, Octasic'));
      expect(textFor('abseil-cpp'), contains('Apache License'));
      expect(textFor('libsrtp'), contains('Cisco Systems, Inc.'));
      expect(textFor('libyuv'), contains('The LibYuv Project Authors'));
      expect(textFor('dav1d'), contains('VideoLAN and dav1d authors'));
      expect(
        textFor('libaom'),
        contains('Alliance for Open Media. All rights reserved.'),
      );

      final raw = await tester.runAsync(
        () => rootBundle.loadString('assets/licenses/WEBRTC_NOTICES.md'),
      );
      final lf = parseWebrtcNoticeEntries(raw!.replaceAll('\r\n', '\n'));
      final crlf = parseWebrtcNoticeEntries(
        raw.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'),
      );
      expect(lf, hasLength(39));
      expect(
        crlf.map((e) => e.packages.toList()),
        lf.map((e) => e.packages.toList()),
      );
    },
  );

  testWidgets('settings open the license page', (tester) async {
    // 설정 목록 전체가 한 화면에 표시되도록 뷰포트 높이를 충분히 확보함
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();
    await tester.tap(find.text('Open-source licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
