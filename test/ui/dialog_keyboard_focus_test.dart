import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // macOS·iOS(외장 키보드)와 Apple 기기 브라우저의 웹 앱은 Cupertino 대화상자를 씀:
  // 버튼에 Tab이 닿고 Enter·Space로 눌려야 키보드만으로 보안 코드 확인 등을 끝낼 수 있음
  Future<List<String>> pumpCupertino(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(
          builder: (context) {
            final cupertino = isCupertinoDialog(context);
            return Scaffold(
              body: AppAlertDialog(
                cupertino: cupertino,
                title: const Text('Wipe everything?'),
                actions: [
                  for (final label in ['Cancel', 'Wipe'])
                    AdaptiveDialogAction(
                      cupertino: cupertino,
                      label: label,
                      onPressed: () => pressed.add(label),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDialogAction), findsNWidgets(2));
    return pressed;
  }

  bool focused(WidgetTester tester, String label) =>
      Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('${platform.name} dialog buttons take Tab, Enter and Space', (
      tester,
    ) async {
      final pressed = await pumpCupertino(tester, platform);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(tester, 'Cancel'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(tester, 'Wipe'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['Wipe']);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(focused(tester, 'Cancel'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, ['Wipe', 'Cancel']);
    });

    testWidgets('${platform.name} dialog buttons still answer one tap once', (
      tester,
    ) async {
      final pressed = await pumpCupertino(tester, platform);
      await tester.tap(find.text('Wipe'));
      await tester.pumpAndSettle();
      expect(pressed, ['Wipe']);
    });
  }
}
