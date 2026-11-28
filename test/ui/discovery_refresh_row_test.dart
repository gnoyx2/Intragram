import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/home/widgets/discovery_refresh_row.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/store/models.dart';

class _SpyDiscovery extends DiscoveryController {
  int refreshCalls = 0;
  final periodic = <bool>[];

  @override
  List<PeerDevice> build() => const <PeerDevice>[];

  @override
  Future<void> refresh({bool periodic = false}) async {
    refreshCalls++;
    this.periodic.add(periodic);
  }
}

void main() {
  testWidgets('Reduce Motion keeps the refresh interval at 20 seconds', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final spy = _SpyDiscovery();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [discoveryControllerProvider.overrideWith(() => spy)],
        child: const MaterialApp(home: Scaffold(body: DiscoveryRefreshRow())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(spy.refreshCalls, 0);
    await tester.pump(const Duration(seconds: 18));
    // 애니메이션 완료는 주기가 지난 뒤 첫 프레임에서야 알려짐
    await tester.pump(const Duration(milliseconds: 1));
    expect(spy.refreshCalls, 1);
    // 주기 새로고침은 periodic으로 알려서 Linux가 살아 있는 스캔을 안 갈아끼우게 함
    expect(spy.periodic, [true]);
  });
  testWidgets('shows a countdown and refresh button, tapping calls refresh', (
    tester,
  ) async {
    final spy = _SpyDiscovery();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [discoveryControllerProvider.overrideWith(() => spy)],
        child: const MaterialApp(home: Scaffold(body: DiscoveryRefreshRow())),
      ),
    );
    await tester.pump();

    expect(find.textContaining('20'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(spy.refreshCalls, 1);
  });
}
