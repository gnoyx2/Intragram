import 'package:flutter/widgets.dart' show StringCharacters;

// 앞에서 max 글자까지만 남김. 글자는 화면에 보이는 단위라 이모지나 조합 글자가 중간에 안 잘림.
// 안 잘렸으면 받은 문자열 그대로 돌려줌 (길이 비교로 잘렸는지 앎)
String clipCharacters(String text, int max) =>
    text.length <= max ? text : text.characters.take(max).string;
