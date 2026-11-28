import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/widgets/field_name.dart';

import '_harness.dart';

List<SemanticsData> _buttons(WidgetTester tester) {
  final out = <SemanticsData>[];
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isButton && !node.isMergedIntoParent) {
      out.add(data);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return out;
}

int _close(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')' && --depth == 0) return i;
  }
  return src.length;
}

void main() {
  testWidgets('a hint-only field keeps its name once it has text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: FieldName(
            controller: controller,
            name: 'Message',
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Message'),
            ),
          ),
        ),
      ),
    );
    String label() =>
        tester.getSemantics(find.byType(EditableText)).getSemanticsData().label;
    final node = tester.getSemantics(find.byType(EditableText)).id;
    expect(label(), 'Message');
    controller.text = 'draft';
    await tester.pumpAndSettle();
    expect(label(), 'Message');
    // 노드가 바뀌면 웹 엔진이 입력 요소를 새로 만들어 치던 글이 사라짐 (label null↔문구 전환에서 실제로 났음)
    expect(tester.getSemantics(find.byType(EditableText)).id, node);
    expect(
      tester.getSemantics(find.byType(EditableText)).getSemanticsData().value,
      'draft',
    );
    handle.dispose();
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} home buttons each have one name',
      (tester) async {
        final handle = tester.ensureSemantics();
        final h = Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(h.wrap(const HomeScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final icons = _buttons(tester).where((b) => b.tooltip.isNotEmpty);
        expect(icons.length, greaterThanOrEqualTo(4));
        for (final button in icons) {
          // macOS·Linux 앱 브리지는 tooltip을 버림: 같은 문구가 label이어야 스크린 리더가 읽음.
          // 다른 플랫폼은 tooltip이 이름이라 label까지 붙이면 두 번 읽힘
          expect(
            button.label,
            platform == TargetPlatform.windows ? isEmpty : button.tooltip,
            reason: button.tooltip,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        handle.dispose();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  test(
    'icon buttons, menus and status tooltips name themselves on macOS and Linux',
    () {
      final call = RegExp(
        r'(?<![A-Za-z.])(?:IconButton(?:\.\w+)?|PopupMenuButton<[^>]*>|'
        r'FloatingActionButton(?:\.\w+)?|Tooltip)\(',
      );
      var checked = 0;
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final src = file.readAsStringSync();
        for (final m in call.allMatches(src)) {
          if (src.startsWith('IconButton.styleFrom', m.start)) continue;
          final args = src.substring(m.end, _close(src, m.end - 1));
          final named = m[0] == 'Tooltip(' || args.contains('tooltip:');
          if (!named || args.contains('excludeFromSemantics: true')) continue;
          checked++;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          expect(args, contains('tooltipLabel('), reason: '${file.path}:$line');
        }
      }
      expect(checked, greaterThan(30));
    },
  );

  test(
    'hint-only text fields sit inside FieldName or a labelled Semantics',
    () {
      final field = RegExp(r'(?<![A-Za-z])(?:Cupertino)?TextField\(');
      var checked = 0;
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final src = file.readAsStringSync();
        final wrappers = [
          for (final w in RegExp(r'(?:FieldName|Semantics)\(').allMatches(src))
            (w.start, _close(src, w.end - 1)),
        ];
        for (final m in field.allMatches(src)) {
          final args = src.substring(m.end, _close(src, m.end - 1));
          final hintOnly =
              (args.contains('hintText:') || args.contains('placeholder:')) &&
              !args.contains('labelText:');
          if (!hintOnly) continue;
          checked++;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          expect(
            wrappers.any((w) => w.$1 < m.start && m.start < w.$2),
            isTrue,
            reason: '${file.path}:$line',
          );
        }
      }
      expect(checked, greaterThanOrEqualTo(5));
    },
  );
}
