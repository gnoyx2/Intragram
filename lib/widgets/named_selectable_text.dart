import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// 골라서 복사할 수 있는 글. Flutter 웹은 읽기 전용 글상자의 값을 접근성 트리에 안 내보내서
// (이름도 값도 없는 빈 textbox) 스크린 리더가 peer ID·자격·증적 본문을 못 읽음: 웹에서만 같은 글을 이름으로 줌.
// 앱은 네이티브 접근성 브리지가 값을 그대로 읽어서 건드리지 않음
class NamedSelectableText extends StatelessWidget {
  const NamedSelectableText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      SelectableText(text, style: style, semanticsLabel: kIsWeb ? text : null);
}
