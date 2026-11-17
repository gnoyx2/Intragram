import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/widgets/privacy_shield.dart';

// 폰 앱은 앱 전환기로 가는 inactive부터 덮음. 폰 브라우저는 권한 창·공유 시트만 떠도 inactive가 되고
// 닫힌 뒤에도 포커스가 바로 안 돌아와 흐림이 남음 (숨긴 탭엔 어차피 프레임을 못 그림)
void main() {
  for (final web in [false, true]) {
    testWidgets(
      'phone ${web ? 'browser' : 'app'} shield on inactive: ${!web}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PrivacyShield(web: web, child: const Text('secret')),
          ),
        );
        Future<void> move(AppLifecycleState state) async {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }

        final shield = find.byType(BackdropFilter);
        await move(AppLifecycleState.inactive);
        expect(shield, web ? findsNothing : findsOneWidget);
        await move(AppLifecycleState.resumed);
        expect(shield, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
