import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 폰(특히 브라우저)에선 키보드가 올라오면 보이는 높이가 480 밑으로 떨어져 대화상자가 낮은 창 배치로 바뀜.
// 그때 입력칸이 새로 만들어지면 포커스와 키보드가 바로 사라져 아무것도 못 씀
void main() {
  testWidgets(
    'dialog text field keeps focus when the keyboard lowers the window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 790);
      addTearDown(tester.view.reset);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppAlertDialog(
                  cupertino: false,
                  title: const Text('Join'),
                  content: TextField(focusNode: focus),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    FilledButton(onPressed: () {}, child: const Text('Create')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final field = tester.state(find.byType(EditableText));

      // Chrome Android 789 → 477 CSS px, iPhone Safari도 비슷하게 480 밑으로 내려감
      tester.view.viewInsets = const FakeViewPadding(bottom: 312);
      await tester.pumpAndSettle();
      expect(find.text('Create'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.state(find.byType(EditableText)), same(field));
      expect(tester.testTextInput.hasAnyClients, isTrue);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.state(find.byType(EditableText)), same(field));
    },
  );
}
