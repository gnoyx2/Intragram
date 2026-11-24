import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/network/server_controller.dart';

import '_harness.dart';

class _LockedAccess extends VaultAccessNotifier {
  @override
  VaultAccessState build() => const VaultLocked();
}

// Android 엔진은 실행 중 바뀐 12/24시간 설정을 다시 안 보냄: 앱으로 돌아올 때 OS 값을 읽어 MediaQuery를
// 덮어야 앱을 다시 켜지 않아도 시각이 바뀜
void main() {
  late bool osUses24h;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    osUses24h = true;
    const channel = MethodChannel('intragram/privacy');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'alwaysUse24HourFormat' ? osUses24h : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => OsPrivacy.use24HourFormat.value = null);
  });

  Future<bool> pumpAppUses24h(WidgetTester tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        const IntragramApp(),
        overrides: [
          vaultAccessProvider.overrideWith(_LockedAccess.new),
          notificationBridgeProvider.overrideWith((ref) {}),
          roomHintBridgeProvider.overrideWith((ref) {}),
          screenshotBridgeProvider.overrideWith((ref) {}),
        ],
      ),
    );
    await tester.pump();
    return MediaQuery.alwaysUse24HourFormatOf(
      tester.element(find.byType(PinGateScreen)),
    );
  }

  bool shown(WidgetTester tester) => MediaQuery.alwaysUse24HourFormatOf(
    tester.element(find.byType(PinGateScreen)),
  );

  testWidgets(
    'Android follows a 12/24 h change when the app comes back',
    (tester) async {
      await pumpAppUses24h(tester);

      await OsPrivacy.refreshAccessibility();
      await tester.pump();
      expect(shown(tester), isTrue);

      osUses24h = false;
      await OsPrivacy.refreshAccessibility();
      await tester.pump();
      expect(shown(tester), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'other platforms keep the engine value and never ask',
    (tester) async {
      final before = await pumpAppUses24h(tester);

      await OsPrivacy.refreshAccessibility();
      await tester.pump();
      expect(shown(tester), before);
      expect(calls, isNot(contains('alwaysUse24HourFormat')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
