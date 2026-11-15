import 'package:flutter/widgets.dart';

// 힌트(placeholder)만 있는 입력칸은 글을 쓰면 힌트가 투명해지며 접근성 이름이 사라짐 (앱·웹 공통 Flutter 동작).
// 글이 있을 때만 같은 이름을 붙임: 빈 칸은 힌트가 이름이라 겹쳐 읽히지 않음.
// label은 null이 아니라 ''로 비움: Semantics 구조가 바뀌면 웹 엔진이 입력 요소를 새로 만들어 치던 글이 사라짐
class FieldName extends StatelessWidget {
  const FieldName({
    super.key,
    required this.controller,
    required this.name,
    required this.child,
  });

  final TextEditingController controller;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, field) =>
            Semantics(label: value.text.isEmpty ? '' : name, child: field),
        child: child,
      );
}
