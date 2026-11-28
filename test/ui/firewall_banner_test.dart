import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/home/widgets/firewall_banner.dart';

import '_harness.dart';

void main() {
  testWidgets('the firewall warning explains the block and offers settings', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const Scaffold(body: FirewallBanner())));
    await tester.pump();
    expect(
      find.text('Windows Firewall is blocking incoming connections'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Open Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
