import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';

import '_harness.dart';

// Android 17 에뮬레이터에서 재현: 대화 입력칸에 키보드가 열린 채 뒤로를 한 번 누르면 키보드와 대화가 같이 닫혔음.
// 대화는 홈의 창 Navigator(NavigatorPopHandler) 안에 있어 그쪽이 IME보다 먼저 뒤로를 받음
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets(
    'Android Back with the keyboard open only closes the keyboard',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.store.upsertConversation(conv('c1', secure: true));
      await tester.pumpWidget(h.wrap(const HomeScreen()));
      await tester.pump();
      await tester.tap(find.text('bob-owl-22').first);
      await settle(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        find.byType(ChatRoomScreen),
        findsOneWidget,
        reason: 'the first Back only hides the keyboard',
      );

      tester.view.resetViewInsets();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ChatRoomScreen), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
